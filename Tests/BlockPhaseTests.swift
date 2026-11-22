import Foundation

@main
struct BlockPhaseTests {
    static func main() throws {
        var daily = BlockPhase.tracking
        precondition(!daily.isShielded)
        precondition(!daily.canGrantBonus)
        precondition(!daily.beginBonus(until: .distantFuture))
        daily.reachLimit()
        daily.reachLimit()
        precondition(daily == .blocked && daily.isShielded)
        precondition(daily.canGrantBonus)

        let end = Date(timeIntervalSince1970: 1_000)
        precondition(daily.beginBonus(until: end))
        precondition(daily.isShielded)
        precondition(!daily.canGrantBonus)
        precondition(!daily.beginBonus(until: end))
        daily.cancelBonusSetup()
        precondition(daily == .blocked)
        precondition(daily.canGrantBonus)

        precondition(daily.beginBonus(until: end))
        daily.activateBonus()
        precondition(!daily.isShielded)
        precondition(!daily.canGrantBonus)
        daily.reachLimit()
        daily.expireBonus(at: end.addingTimeInterval(-1))
        precondition(daily == .bonus(until: end))
        daily.expireBonus(at: end)
        precondition(daily == .locked && daily.isShielded)
        precondition(!daily.canGrantBonus)
        precondition(!daily.beginBonus(until: .distantFuture))
        daily.cancelBonusSetup()
        daily.activateBonus()
        precondition(daily == .locked)

        var pending = BlockPhase.blocked
        precondition(pending.beginBonus(until: end))
        pending.finishBonus()
        pending.activateBonus()
        precondition(pending == .locked)

        var stale = BlockPhase.blocked
        stale.finishBonus()
        precondition(stale == .blocked)

        var consumed = BlockPhase.blocked
        precondition(consumed.beginBonus(until: end))
        consumed.activateBonus()
        consumed.finishBonus()
        precondition(consumed == .locked)

        let restored = try JSONDecoder().decode(
            BlockPhase.self, from: JSONEncoder().encode(BlockPhase.locked)
        )
        precondition(restored == .locked && restored.isShielded)
        print("CapTemps block state tests passed.")
    }
}
