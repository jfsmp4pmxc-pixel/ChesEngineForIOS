import SwiftUI

/// Names of the piece images in the asset catalog (see scripts/gen_assets.py).
enum PieceArt {
    static func assetName(_ piece: Piece) -> String {
        let side = piece.side == .white ? "w" : "b"
        let letter: String
        switch piece.type {
        case .pawn: letter = "P"
        case .knight: letter = "N"
        case .bishop: letter = "B"
        case .rook: letter = "R"
        case .queen: letter = "Q"
        case .king: letter = "K"
        }
        return "piece_" + side + letter
    }
}

/// A chess piece drawn from the asset catalog. If the image is missing for any
/// reason, a text glyph is drawn instead so the board never ends up empty.
struct PieceImage: View {
    let piece: Piece
    let size: CGFloat
    @AppStorage(Theme.assetsVersionKey) private var assetsVersion = 0

    var body: some View {
        let name = PieceArt.assetName(piece)
        if let custom = CustomAssets.image(named: name) {
            Image(uiImage: custom)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else if UIImage(named: name) != nil {
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Text(piece.glyph)
                .font(.system(size: size * 0.8))
                .foregroundColor(piece.side == .white ? .white : .black)
                .shadow(color: Color.black.opacity(piece.side == .white ? 0.9 : 0.0), radius: 0.8)
                .frame(width: size, height: size)
        }
    }
}

/// Round badge showing how good a move was (Brilliant, Blunder, ...).
struct ClassIcon: View {
    let cls: MoveClass
    @AppStorage(Theme.assetsVersionKey) private var assetsVersion = 0

    var body: some View {
        if let custom = CustomAssets.image(named: cls.iconName) {
            Image(uiImage: custom)
                .resizable()
                .scaledToFit()
        } else if UIImage(named: cls.iconName) != nil {
            Image(cls.iconName)
                .resizable()
                .scaledToFit()
        } else {
            Circle()
                .fill(cls.color)
                .overlay(
                    Text(cls.symbol)
                        .font(.system(size: 12, weight: .bold))
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .foregroundColor(.white)
                        .padding(2)
                )
        }
    }
}
