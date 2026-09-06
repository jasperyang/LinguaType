import Foundation

enum DictionaryLookupError: Error {
    case invalidResponse
    case serverStatus(Int)
}

final class DictionaryRequestLimiter {
    private struct Pending {
        let providerID: String
        let start: () -> Void
    }

    private let globalLimit: Int
    private let providerLimit: Int
    private let lock = NSLock()
    private var activeTotal = 0
    private var activeByProvider: [String: Int] = [:]
    private var pending: [Pending] = []

    init(globalLimit: Int = 4, providerLimit: Int = 2) {
        self.globalLimit = globalLimit
        self.providerLimit = providerLimit
    }

    func enqueue(providerID: String, start: @escaping () -> Void) {
        lock.lock()
        if canStart(providerID: providerID) {
            markStarted(providerID: providerID)
            lock.unlock()
            start()
        } else {
            pending.append(Pending(providerID: providerID, start: start))
            lock.unlock()
        }
    }

    func finish(providerID: String) {
        var starts: [() -> Void] = []
        lock.lock()
        activeTotal = max(0, activeTotal - 1)
        activeByProvider[providerID] = max(0, (activeByProvider[providerID] ?? 0) - 1)
        while activeTotal < globalLimit,
              let index = pending.firstIndex(where: { canStart(providerID: $0.providerID) }) {
            let next = pending.remove(at: index)
            markStarted(providerID: next.providerID)
            starts.append(next.start)
        }
        lock.unlock()
        starts.forEach { $0() }
    }

    private func canStart(providerID: String) -> Bool {
        activeTotal < globalLimit && (activeByProvider[providerID] ?? 0) < providerLimit
    }

    private func markStarted(providerID: String) {
        activeTotal += 1
        activeByProvider[providerID, default: 0] += 1
    }
}

final class DictionaryLookupService {
    private let session: URLSession
    private let cache: DictionaryCache
    private let limiter: DictionaryRequestLimiter
    private let logger: (String) -> Void

    init(
        session: URLSession = .shared,
        cache: DictionaryCache = DictionaryCache(),
        limiter: DictionaryRequestLimiter = DictionaryRequestLimiter(),
        logger: @escaping (String) -> Void = { NSLog("LinguaType dictionary: \($0)") }
    ) {
        self.session = session
        self.cache = cache
        self.limiter = limiter
        self.logger = logger
    }

    func lookup(
        provider: any DictionaryProvider,
        query: DictionaryQuery,
        completion: @escaping (Result<DictionaryEntry?, Error>) -> Void
    ) {
        let key = DictionaryCache.Key(providerID: provider.id, query: query)
        if let cached = cache.entry(for: key) {
            logger("provider=\(provider.id) cache=hit")
            completion(.success(cached))
            return
        }
        if cache.hasFreshNegative(for: key) {
            logger("provider=\(provider.id) cache=negative-hit")
            completion(.success(nil))
            return
        }

        do {
            let request = try provider.makeRequest(for: query)
            limiter.enqueue(providerID: provider.id) { [weak self] in
                guard let self else { return }
                self.perform(request: request, provider: provider, query: query, key: key, attempt: 0) { result in
                    self.limiter.finish(providerID: provider.id)
                    completion(result)
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    func lookup(
        providers: [any DictionaryProvider],
        query: DictionaryQuery,
        completion: @escaping (Result<DictionaryEntry?, Error>) -> Void
    ) {
        guard !providers.isEmpty else {
            completion(.success(nil))
            return
        }
        lookup(providers: providers, query: query, index: 0, completion: completion)
    }

    func clearCache() { cache.clear() }

    private func lookup(
        providers: [any DictionaryProvider],
        query: DictionaryQuery,
        index: Int,
        completion: @escaping (Result<DictionaryEntry?, Error>) -> Void
    ) {
        lookup(provider: providers[index], query: query) { [weak self] result in
            guard let self else { return }
            if case .success(let entry?) = result {
                completion(.success(entry))
            } else if providers.indices.contains(index + 1) {
                self.lookup(providers: providers, query: query, index: index + 1, completion: completion)
            } else {
                completion(result)
            }
        }
    }

    private func perform(
        request: URLRequest,
        provider: any DictionaryProvider,
        query: DictionaryQuery,
        key: DictionaryCache.Key,
        attempt: Int,
        completion: @escaping (Result<DictionaryEntry?, Error>) -> Void
    ) {
        let started = Date()
        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            if let error {
                if attempt == 0, self.isRetryable(error) {
                    self.logger("provider=\(provider.id) retry=1 reason=network")
                    self.perform(request: request, provider: provider, query: query, key: key, attempt: 1, completion: completion)
                } else {
                    self.cache.storeNegative(for: key)
                    self.logger("provider=\(provider.id) status=network-error elapsed_ms=\(Int(Date().timeIntervalSince(started) * 1000))")
                    completion(.failure(error))
                }
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(DictionaryLookupError.invalidResponse))
                return
            }
            if (500..<600).contains(http.statusCode), attempt == 0 {
                self.logger("provider=\(provider.id) retry=1 status=\(http.statusCode)")
                self.perform(request: request, provider: provider, query: query, key: key, attempt: 1, completion: completion)
                return
            }
            do {
                let entry = try provider.decode(data ?? Data(), response: http, query: query)
                if let entry {
                    self.cache.store(entry, for: key)
                } else {
                    self.cache.storeNegative(for: key)
                }
                self.logger("provider=\(provider.id) status=\(http.statusCode) elapsed_ms=\(Int(Date().timeIntervalSince(started) * 1000))")
                completion(.success(entry))
            } catch {
                self.cache.storeNegative(for: key)
                self.logger("provider=\(provider.id) status=decode-error elapsed_ms=\(Int(Date().timeIntervalSince(started) * 1000))")
                completion(.failure(error))
            }
        }.resume()
    }

    private func isRetryable(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return [.timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
                .dnsLookupFailed, .notConnectedToInternet].contains(urlError.code)
    }
}
