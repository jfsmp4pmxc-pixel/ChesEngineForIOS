import Foundation

/// Vietnamese display text for values that are stored in English (saved games and
/// PGN keep the English wording so files stay portable and old games still load).
enum Vi {
    static func termination(_ text: String) -> String {
        switch text {
        case "Checkmate": return "Chiếu hết"
        case "Stalemate": return "Bí cờ"
        case "Insufficient material": return "Không đủ quân để chiếu hết"
        case "Fifty-move rule": return "Luật 50 nước"
        case "Threefold repetition": return "Lặp thế 3 lần"
        case "Time forfeit": return "Hết giờ"
        case "Resignation": return "Đầu hàng"
        case "Draw agreed": return "Hai bên đồng ý hòa"
        default: return text
        }
    }
}
