import SwiftUI

/// Visual identity per category (docs/design-system.md#color--categories). Single source of truth.
extension Category {
    var symbolName: String {
        switch self {
        case .produce: "carrot.fill"
        case .bakery: "birthday.cake.fill"
        case .dairy: "cup.and.saucer.fill"
        case .meatAndFish: "fish.fill"
        case .pantry: "takeoutbag.and.cup.and.straw.fill"
        case .frozen: "snowflake"
        case .drinks: "wineglass.fill"
        case .household: "house.fill"
        case .personalCare: "heart.fill"
        case .other: "basket.fill"
        }
    }

    var tint: Color {
        switch self {
        case .produce: .green
        case .bakery: .brown
        case .dairy: .cyan
        case .meatAndFish: .red
        case .pantry: .orange
        case .frozen: .teal
        case .drinks: .purple
        case .household: .indigo
        case .personalCare: .pink
        case .other: .gray
        }
    }
}

/// Small tinted circle with the category symbol, used in rows and section headers.
struct CategoryBadge: View {
    let category: Category
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: category.symbolName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(category.tint)
            .frame(width: size, height: size)
            .background(category.tint.opacity(0.15), in: .circle)
            .accessibilityHidden(true)
    }
}
