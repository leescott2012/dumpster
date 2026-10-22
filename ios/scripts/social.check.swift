// Run: swiftc -parse-as-library ios/DumpsterIOS/SocialLogic.swift ios/scripts/social.check.swift -o /tmp/sc && /tmp/sc
import Foundation

func check(_ c: Bool, _ m: String) { if !c { print("FAIL: \(m)"); exit(1) } }

@main struct Check {
    static func main() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "America/New_York")!
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 15))!
        check(SocialLogic.localDay(now, calendar: cal) == "2026-10-22", "day key")
        let late = cal.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 23, minute: 59))!
        check(SocialLogic.localDay(late, calendar: cal) == "2026-01-05", "day key pads, local")

        check(SocialLogic.dmTitle("@sam", 1) == "New message from @sam", "dm 1")
        check(SocialLogic.dmTitle("@sam", 3) == "3 new messages from @sam", "dm 3")
        check(SocialLogic.nextRollingCount(readAt: nil, count: nil, exists: false) == 1, "first")
        check(SocialLogic.nextRollingCount(readAt: nil, count: 2, exists: true) == 3, "unread keeps counting")
        check(SocialLogic.nextRollingCount(readAt: "x", count: 5, exists: true) == 1, "read restarts")

        let day = { (d: Int, h: Int) in cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h))! }
        let items = [day(22, 14), day(22, 9), day(21, 20), day(3, 8)]
        let g = SocialLogic.groupByDay(items, now: now, calendar: cal) { $0 }
        check(g.map { $0.label } == ["Today", "Yesterday", "Oct 3"], "labels \(g.map { $0.label })")
        check(g[0].items.count == 2, "today holds 2")

        check(SocialLogic.parseLink("/connections") == .connections, "link connections")
        check(SocialLogic.parseLink("/taste") == .taste && SocialLogic.parseLink("/credits") == .credits, "link taste/credits")
        let id = "123e4567-e89b-12d3-a456-426614174000"
        check(SocialLogic.parseLink("/messages/\(id)") == .dm(id), "link dm")
        check(SocialLogic.parseLink("/messages/nope") == nil && SocialLogic.parseLink(nil) == nil, "bad links")

        check(SocialLogic.parseDate("2026-10-22T15:04:05.123456+00:00") != nil, "date micros")
        check(SocialLogic.parseDate("2026-10-22T15:04:05Z") != nil, "date plain")
        check(SocialLogic.badgeText(12) == "9+" && SocialLogic.badgeText(4) == "4", "badge")
        print("social checks passed")
    }
}
