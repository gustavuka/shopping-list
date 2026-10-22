import Foundation

/// Guesses a store section from an item name. English and Portuguese keywords, accent- and case-insensitive.
/// Cheap enough to run on every keystroke-free add; no allocations beyond tokenizing the name.
enum CategoryGuesser {
    static func guess(_ name: String) -> Category {
        let normalized = normalize(name)
        guard !normalized.isEmpty else { return .other }

        // Phrases first, so "peanut butter" beats "butter" and "pasta de dente" beats "pasta".
        for category in priority {
            if let phrases = keywords[category]?.phrases,
               phrases.contains(where: { normalized.contains($0) }) {
                return category
            }
        }

        let tokens = normalized.split(whereSeparator: { !$0.isLetter }).map(String.init)
        for category in priority {
            guard let words = keywords[category]?.words else { continue }
            for token in tokens where words.contains(token) || singulars(of: token).contains(where: words.contains) {
                return category
            }
        }
        return .other
    }

    // Specific sections win over broad ones: "frozen peas" → frozen, "chocolate milk" → dairy.
    private static let priority: [Category] = [
        .frozen, .personalCare, .household, .drinks, .meatAndFish, .dairy, .bakery, .pantry, .produce,
    ]

    private static func normalize(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func singulars(of token: String) -> [String] {
        var result: [String] = []
        if token.hasSuffix("es") { result.append(String(token.dropLast(2))) }
        if token.hasSuffix("s") { result.append(String(token.dropLast())) }
        return result
    }

    private struct Keywords {
        var words: Set<String>
        var phrases: [String] = []
    }

    private static let keywords: [Category: Keywords] = [
        .produce: Keywords(words: [
            "apple", "banana", "orange", "lemon", "lime", "grape", "strawberry", "strawberrie", "berry", "berrie",
            "blueberry", "blueberrie", "avocado", "tomato", "potato", "onion", "garlic", "carrot", "lettuce",
            "spinach", "broccoli", "cucumber", "mushroom", "zucchini", "celery", "kale", "herb", "cilantro",
            "parsley", "basil", "ginger", "fruit", "salad", "mango", "pineapple", "melon", "watermelon", "pear",
            "peach", "pepper", "pea",
            "maca", "laranja", "limao", "uva", "morango", "abacate", "tomate", "batata", "cebola", "alho",
            "cenoura", "alface", "espinafre", "brocolis", "pepino", "pimentao", "cogumelo", "abobrinha", "salsa",
            "coentro", "manjericao", "gengibre", "fruta", "mamao", "abacaxi", "melancia", "pera", "pessego",
            "manga", "rucula", "couve", "salada",
        ]),
        .bakery: Keywords(words: [
            "bread", "bagel", "croissant", "baguette", "bun", "tortilla", "cake", "muffin", "roll",
            "pao", "paes", "bolo", "torrada", "broa",
        ]),
        .dairy: Keywords(words: [
            "milk", "cheese", "butter", "yogurt", "yoghurt", "cream", "egg",
            "leite", "queijo", "manteiga", "iogurte", "creme", "ovo", "requeijao", "nata",
        ]),
        .meatAndFish: Keywords(words: [
            "chicken", "beef", "pork", "steak", "bacon", "ham", "sausage", "turkey", "salmon", "tuna", "fish",
            "shrimp", "meat", "mince",
            "frango", "carne", "porco", "bife", "presunto", "linguica", "salsicha", "peru", "salmao", "atum",
            "peixe", "camarao", "picanha", "file",
        ]),
        .pantry: Keywords(
            words: [
                "rice", "pasta", "spaghetti", "flour", "sugar", "salt", "oil", "vinegar", "bean", "lentil",
                "cereal", "oat", "honey", "jam", "coffee", "tea", "sauce", "ketchup", "mustard", "mayo",
                "mayonnaise", "spice", "soup", "chocolate", "cookie", "cracker", "chip", "nut",
                "arroz", "macarrao", "farinha", "acucar", "sal", "oleo", "azeite", "vinagre", "feijao", "lentilha",
                "aveia", "mel", "geleia", "cafe", "cha", "molho", "mostarda", "maionese", "biscoito", "bolacha",
            ],
            phrases: ["peanut butter", "black pepper", "olive oil", "tomato sauce", "molho de tomate"]
        ),
        .frozen: Keywords(
            words: ["frozen", "popsicle", "sorvete", "congelado", "congelada", "picole"],
            phrases: ["ice cream"]
        ),
        .drinks: Keywords(words: [
            "water", "juice", "soda", "beer", "wine", "coke", "kombucha",
            "agua", "suco", "refrigerante", "cerveja", "vinho",
        ]),
        .household: Keywords(
            words: [
                "detergent", "sponge", "trash", "bleach", "foil", "napkin", "battery", "batterie", "laundry",
                "detergente", "esponja", "lixo", "sabao", "amaciante", "guardanapo", "pilha",
            ],
            phrases: [
                "dish soap", "paper towel", "toilet paper", "trash bag", "papel higienico", "papel toalha",
                "saco de lixo", "agua sanitaria",
            ]
        ),
        .personalCare: Keywords(
            words: [
                "shampoo", "conditioner", "toothpaste", "toothbrush", "deodorant", "soap", "razor", "lotion",
                "sunscreen", "floss",
                "sabonete", "desodorante", "condicionador", "protetor",
            ],
            phrases: ["pasta de dente", "escova de dente", "fio dental"]
        ),
    ]
}
