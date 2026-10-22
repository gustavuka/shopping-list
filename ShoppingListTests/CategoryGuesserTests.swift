import Testing
@testable import ShoppingList

struct CategoryGuesserTests {
    @Test(arguments: [
        ("Milk", Category.dairy),
        ("eggs", .dairy),
        ("Bananas", .produce),
        ("tomatoes", .produce),
        ("Sourdough bread", .bakery),
        ("Chicken thighs", .meatAndFish),
        ("Olive oil", .pantry),
        ("peanut butter", .pantry),
        ("Frozen peas", .frozen),
        ("Ice cream", .frozen),
        ("chocolate milk", .dairy),
        ("Sparkling water", .drinks),
        ("Toilet paper", .household),
        ("dish soap", .household),
        ("Toothpaste", .personalCare),
        ("Batteries", .household),
        ("Something weird", .other),
        ("", .other),
    ])
    func guessesEnglish(name: String, expected: Category) {
        #expect(CategoryGuesser.guess(name) == expected)
    }

    @Test(arguments: [
        ("Leite", Category.dairy),
        ("Pão francês", .bakery),
        ("MAÇÃS", .produce),
        ("Feijão preto", .pantry),
        ("Água sanitária", .household),
        ("Água com gás", .drinks),
        ("Pasta de dente", .personalCare),
        ("Sorvete de chocolate", .frozen),
        ("Picanha", .meatAndFish),
    ])
    func guessesPortuguese(name: String, expected: Category) {
        #expect(CategoryGuesser.guess(name) == expected)
    }
}
