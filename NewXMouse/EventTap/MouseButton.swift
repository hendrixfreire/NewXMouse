import Foundation

enum MouseButton: Int, Codable, CaseIterable, Identifiable, Comparable {
    case left = 0
    case right = 1
    case middle = 2
    case side1 = 3     // Back / Button 4
    case side2 = 4     // Forward / Button 5
    case extra1 = 5
    case extra2 = 6
    case extra3 = 7
    case scrollUp = 100
    case scrollDown = 101

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .left: return "Left Click"
        case .right: return "Right Click"
        case .middle: return "Middle Click"
        case .side1: return "Side Back (Button 4)"
        case .side2: return "Side Forward (Button 5)"
        case .extra1: return "Extra Button 6"
        case .extra2: return "Extra Button 7"
        case .extra3: return "Extra Button 8"
        case .scrollUp: return "Scroll Up"
        case .scrollDown: return "Scroll Down"
        }
    }

    /// Buttons that are commonly remapped (excludes left click by default)
    static var remappable: [MouseButton] {
        [.right, .middle, .side1, .side2, .extra1, .extra2, .extra3, .scrollUp, .scrollDown]
    }

    /// Whether this is a scroll wheel "button"
    var isScroll: Bool {
        self == .scrollUp || self == .scrollDown
    }

    static func < (lhs: MouseButton, rhs: MouseButton) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
