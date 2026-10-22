import Foundation

/// Store sections. Case order is the order sections appear in the list (roughly a store walk).
/// Raw values are stored in `items.category` — never change them without a migration.
enum Category: String, CaseIterable, Codable, Sendable, Identifiable {
    case produce
    case bakery
    case dairy
    case meatAndFish = "meat_fish"
    case pantry
    case frozen
    case drinks
    case household
    case personalCare = "personal_care"
    case other

    var id: String { rawValue }

    var displayName: LocalizedStringResource {
        switch self {
        case .produce: "Produce"
        case .bakery: "Bakery"
        case .dairy: "Dairy & Eggs"
        case .meatAndFish: "Meat & Fish"
        case .pantry: "Pantry"
        case .frozen: "Frozen"
        case .drinks: "Drinks"
        case .household: "Household"
        case .personalCare: "Personal Care"
        case .other: "Other"
        }
    }

    init(storedValue: String) {
        self = Category(rawValue: storedValue) ?? .other
    }
}
