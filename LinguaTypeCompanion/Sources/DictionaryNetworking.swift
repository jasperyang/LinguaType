import Foundation

enum DictionaryLookupError: Error {
    case invalidResponse
    case serverStatus(Int)
}

final class DictionaryLookupService {
    private let session: URLSession
    private let cache: DictionaryCache
    private let logger: (String) -> Void

    init(
        session: URLSession = .shared,
        cache: DictionaryCache = DictionaryCache(),
        logger: @escaping (String) -> Void = { NSLog("LinguaType dictionary: \($0)") }
    ) {
        self.session = session
        self.cache = cache
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
            perform(request: request, provider: provider, query: query, key: key, attempt: 0, completion: completion)
        } catch {
            completion(.failure(error))
        }
    }

    func clearCache() { cache.clear() }

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
