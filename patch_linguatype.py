#!/usr/bin/env python3
from __future__ import annotations
import plistlib
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
HERE = Path(__file__).resolve().parent

OLD_BUNDLE = "com.isaac.inputmethod.RimeBuffer"
NEW_BUNDLE = "io.linguatype.inputmethod"
OLD_MODE = "com.isaac.inputmethod.RimeBuffer.Hans"
NEW_MODE = "io.linguatype.inputmethod.Hans"
OLD_CONNECTION = "RimeBuffer_1_Connection"
NEW_CONNECTION = "LinguaType_1_Connection"


def fail(msg: str) -> None:
    raise SystemExit(f"LinguaType patch failed: {msg}")


def read(path: str) -> str:
    p = ROOT / path
    if not p.exists():
        fail(f"missing upstream file: {path}")
    return p.read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    p = ROOT / path
    p.write_text(text, encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        fail(f"expected exactly one {label} anchor, found {count}")
    return text.replace(old, new, 1)


def global_identity_rewrite() -> None:
    suffixes = {".swift", ".sh", ".plist", ".strings", ".md", ".yaml", ".yml", ".json"}
    skip_dirs = {".git", ".build", "Vendor"}
    for p in ROOT.rglob("*"):
        if not p.is_file() or p.suffix not in suffixes:
            continue
        if any(part in skip_dirs for part in p.parts):
            continue
        try:
            s = p.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        n = (s.replace(OLD_MODE, NEW_MODE)
               .replace(OLD_BUNDLE, NEW_BUNDLE)
               .replace(OLD_CONNECTION, NEW_CONNECTION)
               .replace("ETInput.app", "LinguaType.app")
               .replace("Library/RimeBuffer", "Library/RimeLinguaType"))
        if n != s:
            p.write_text(n, encoding="utf-8")


def patch_info_plist() -> None:
    p = ROOT / "Info.plist"
    with p.open("rb") as f:
        info = plistlib.load(f)
    info["CFBundleDisplayName"] = "LinguaType"
    info["CFBundleName"] = "LinguaType"
    info["CFBundleExecutable"] = "LinguaType"
    info["CFBundleIdentifier"] = NEW_BUNDLE
    info["LSMinimumSystemVersion"] = "15.0"
    info["InputMethodConnectionName"] = NEW_CONNECTION
    info["TISInputSourceID"] = NEW_BUNDLE
    info.pop("NSBonjourServices", None)
    info.pop("NSLocalNetworkUsageDescription", None)
    with p.open("wb") as f:
        plistlib.dump(info, f, fmt=plistlib.FMT_XML, sort_keys=False)


def patch_product_identity() -> None:
    path = "Sources/RimeBuffer/ProductIdentity.swift"
    s = read(path)
    s = s.replace('static let displayName = "RIMES"', 'static let displayName = "LinguaType"')
    write(path, s)


def patch_package() -> None:
    path = "Package.swift"
    s = read(path)
    n = re.sub(r"\.macOS\(\.v13\)", ".macOS(.v15)", s)
    n = n.replace('.macOS("13.0")', '.macOS("15.0")')
    if n == s:
        # Do not fail if upstream has already moved to macOS 15+.
        m = re.search(r"\.macOS\([^\n]+\)", s)
        if not m:
            fail("could not locate macOS platform in Package.swift")
    write(path, n)


def patch_build_install() -> None:
    path = "build_install.sh"
    s = read(path)
    # identity rewrite already changed the .app path; executable is deliberately
    # unique too so installing LinguaType never pkill's a co-installed RIMES.
    s2, count = re.subn(r'^EXE="ETInput"', 'EXE="LinguaType"', s, count=1, flags=re.M)
    if count != 1:
        fail(f"build_install.sh executable anchor count={count}")
    s = s2
    # Branding in final install messages only; leave variable names untouched.
    s = s.replace("Installed, registered, and enabled RIMES.",
                  "Installed, registered, and enabled LinguaType.")
    s = s.replace("Installed RIMES; registration/enablement is pending session refresh.",
                  "Installed LinguaType; registration/enablement is pending session refresh.")
    s = s.replace("If RIMES doesn't appear in the input menu", "If LinguaType doesn't appear in the input menu")
    s = s.replace("then add RIMES in System Settings", "then add LinguaType in System Settings")
    write(path, s)


def patch_candidate_window() -> None:
    path = "Sources/RimeBuffer/CandidateWindow.swift"
    s = read(path)

    update_anchor = """        applyAppearance()\n        renderCandidates()\n        layoutAndShowAccordingToPresentation()\n    }\n\n    func hide(owner: FocusToken) {\n"""
    update_replacement = """        applyAppearance()\n        renderCandidates()\n        layoutAndShowAccordingToPresentation()\n        LinguaTypeLearningCoordinator.shared.candidateDidChange(\n            text: selectedCandidateText,\n            anchor: caretRect,\n            presentation: presentation\n        )\n    }\n\n    func hide(owner: FocusToken) {\n        LinguaTypeLearningCoordinator.shared.hide()\n"""
    s = replace_once(s, update_anchor, update_replacement, "CandidateWindow.update/hide")

    hide_all_anchor = """    func hideAll() {\n        hidePanel(reason: \"global-hide\",\n"""
    hide_all_replacement = """    func hideAll() {\n        LinguaTypeLearningCoordinator.shared.hide()\n        hidePanel(reason: \"global-hide\",\n"""
    s = replace_once(s, hide_all_anchor, hide_all_replacement, "CandidateWindow.hideAll")

    move_anchor = """        selectedIndex = clamp(selectedIndex + logicalDelta, count: currentContext.candidates.count)\n        visualPageIndex = pageIndex(containing: selectedIndex, panelWidth: activePanelWidth())\n        renderCandidates()\n        resetCandidateScroll()\n        return true\n    }\n\n    @discardableResult\n    func moveExpandedSelection(rowDelta: Int) -> Bool {\n"""
    move_replacement = """        selectedIndex = clamp(selectedIndex + logicalDelta, count: currentContext.candidates.count)\n        visualPageIndex = pageIndex(containing: selectedIndex, panelWidth: activePanelWidth())\n        renderCandidates()\n        resetCandidateScroll()\n        LinguaTypeLearningCoordinator.shared.candidateDidChange(\n            text: selectedCandidateText,\n            anchor: lastCaretRect,\n            presentation: presentationMode\n        )\n        return true\n    }\n\n    @discardableResult\n    func moveExpandedSelection(rowDelta: Int) -> Bool {\n"""
    s = replace_once(s, move_anchor, move_replacement, "CandidateWindow.moveSelection")

    page_anchor = """        if let first = pages[nextPage].first {\n            selectedIndex = first\n        }\n        renderCandidates()\n        resetCandidateScroll()\n        return true\n    }\n"""
    page_replacement = """        if let first = pages[nextPage].first {\n            selectedIndex = first\n        }\n        renderCandidates()\n        resetCandidateScroll()\n        LinguaTypeLearningCoordinator.shared.candidateDidChange(\n            text: selectedCandidateText,\n            anchor: lastCaretRect,\n            presentation: presentationMode\n        )\n        return true\n    }\n"""
    s = replace_once(s, page_anchor, page_replacement, "CandidateWindow.movePage")
    write(path, s)


def install_learning_source() -> None:
    src = HERE / "patches" / "LinguaTypeLearning.swift"
    dst = ROOT / "Sources" / "RimeBuffer" / "LinguaTypeLearning.swift"
    if not src.exists():
        fail("missing bundled LinguaTypeLearning.swift")
    shutil.copy2(src, dst)


def patch_localizations() -> None:
    resources = ROOT / "Resources"
    if not resources.exists():
        return
    for p in resources.rglob("*.strings"):
        try:
            s = p.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        n = s.replace("RIMES", "LinguaType")
        if n != s:
            p.write_text(n, encoding="utf-8")


def verify() -> None:
    info = plistlib.loads((ROOT / "Info.plist").read_bytes())
    expected = {
        "CFBundleDisplayName": "LinguaType",
        "CFBundleExecutable": "LinguaType",
        "CFBundleIdentifier": NEW_BUNDLE,
        "InputMethodConnectionName": NEW_CONNECTION,
        "TISInputSourceID": NEW_BUNDLE,
        "LSMinimumSystemVersion": "15.0",
    }
    for k, v in expected.items():
        if info.get(k) != v:
            fail(f"Info.plist {k}={info.get(k)!r}, expected {v!r}")
    c = read("Sources/RimeBuffer/CandidateWindow.swift")
    if c.count("LinguaTypeLearningCoordinator.shared.candidateDidChange") < 3:
        fail("candidate learning hooks are incomplete")
    if "LinguaTypeLearningCoordinator.shared.hide()" not in c:
        fail("candidate hide hook missing")
    b = read("build_install.sh")
    if 'APP="LinguaType.app"' not in b or 'EXE="LinguaType"' not in b:
        fail("build_install identity was not isolated")
    r = read("Sources/RimeBuffer/RimeEngine.swift")
    if "Library/RimeLinguaType" not in r:
        fail("Rime user data directory was not isolated")


def main() -> None:
    if not (ROOT / ".git").exists():
        fail(f"{ROOT} is not an RIMES git checkout")
    global_identity_rewrite()
    patch_info_plist()
    patch_product_identity()
    patch_package()
    patch_build_install()
    patch_candidate_window()
    install_learning_source()
    patch_localizations()
    verify()
    print("LinguaType patch applied successfully.")


if __name__ == "__main__":
    main()
