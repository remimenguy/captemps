import Foundation

enum BlockPhase: Codable, Equatable {
    case tracking
    case blocked
    case settingUpBonus(until: Date)
    case bonus(until: Date)
    case locked

    var isShielded: Bool {
        switch self {
        case .blocked, .settingUpBonus, .locked: true
        case .tracking, .bonus: false
        }
    }

    mutating func reachLimit() {
        if self == .tracking { self = .blocked }
    }

    mutating func beginBonus(until: Date) -> Bool {
        guard self == .blocked else { return false }
        self = .settingUpBonus(until: until)
        return true
    }

    mutating func activateBonus() {
        if case .settingUpBonus(let until) = self { self = .bonus(until: until) }
    }

    mutating func cancelBonusSetup() {
        if case .settingUpBonus = self { self = .blocked }
    }

    mutating func finishBonus() {
        switch self {
        case .settingUpBonus, .bonus: self = .locked
        case .tracking, .blocked, .locked: break
        }
    }

    mutating func expireBonus(at date: Date) {
        if case .bonus(let until) = self, date >= until { finishBonus() }
    }
}
