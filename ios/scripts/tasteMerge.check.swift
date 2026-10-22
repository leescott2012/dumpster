// Run: swiftc -parse-as-library ios/DumpsterIOS/TasteMerge.swift ios/scripts/tasteMerge.check.swift -o /tmp/tm && /tmp/tm
import Foundation

func check(_ c: Bool, _ m: String) { if !c { print("FAIL: \(m)"); exit(1) } }

@main struct Check {
    static func main() {
        let mine = "I like dark editorial, gold accents, cars."
        let a = TasteMerge.merge(existing: mine, scrubbed: "Minimalist luxury travel. Short captions. No hashtags.", handle: "catchcanary")
        check(a.hasPrefix(mine), "user text first")
        check(a.contains("--- From Instagram @catchcanary ---") && a.hasSuffix("--- end ---"), "block")
        let b = TasteMerge.merge(existing: a, scrubbed: "Menswear curation. Credits in captions.", handle: "catchcanary")
        check(b.components(separatedBy: "From Instagram").count == 2, "no pile-up")
        check(b.hasPrefix(mine) && b.contains("Menswear") && !b.contains("Minimalist"), "replaced")
        check(TasteMerge.stripIgBlock(b) == mine, "strip")
        let user = String(repeating: "u", count: 1500) + "."
        let c = TasteMerge.merge(existing: user, scrubbed: String(repeating: "Sentence one is here. ", count: 100), handle: "x")
        check(c.count <= 2000 && c.hasPrefix(user) && c.contains("here.\n--- end ---"), "long trimmed at sentence")
        let full = String(repeating: "u", count: 1950)
        check(TasteMerge.merge(existing: full, scrubbed: "Hi.", handle: "x") == full, "no room unchanged")
        print("tasteMerge ok")
    }
}
