import type { Category } from './category'

/**
 * Guesses a store section from an item name. English and Portuguese keywords, accent- and
 * case-insensitive. Port of `Domain/CategoryGuesser.swift` — keep the keyword lists in sync.
 */
export function guessCategory(name: string): Category {
  const normalized = normalize(name)
  if (!normalized) return 'other'

  // Phrases first, so "peanut butter" beats "butter" and "pasta de dente" beats "pasta".
  for (const category of priority) {
    if (keywords[category].phrases?.some((p) => normalized.includes(p))) return category
  }

  const tokens = normalized.split(/[^\p{L}]+/u).filter(Boolean)
  for (const category of priority) {
    const words = keywords[category].words
    for (const token of tokens) {
      if (words.has(token) || singulars(token).some((s) => words.has(s))) return category
    }
  }
  return 'other'
}

type GuessedCategory = Exclude<Category, 'other'>

// Specific sections win over broad ones: "frozen peas" → frozen, "chocolate milk" → dairy.
const priority: GuessedCategory[] = [
  'frozen', 'personal_care', 'household', 'drinks', 'meat_fish', 'dairy', 'bakery', 'pantry', 'produce',
]

function normalize(s: string): string {
  return s.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase().trim()
}

function singulars(token: string): string[] {
  const result: string[] = []
  if (token.endsWith('es')) result.push(token.slice(0, -2))
  if (token.endsWith('s')) result.push(token.slice(0, -1))
  return result
}

const keywords: Record<GuessedCategory, { words: Set<string>; phrases?: string[] }> = {
  produce: {
    words: new Set([
      'apple', 'banana', 'orange', 'lemon', 'lime', 'grape', 'strawberry', 'strawberrie', 'berry', 'berrie',
      'blueberry', 'blueberrie', 'avocado', 'tomato', 'potato', 'onion', 'garlic', 'carrot', 'lettuce',
      'spinach', 'broccoli', 'cucumber', 'mushroom', 'zucchini', 'celery', 'kale', 'herb', 'cilantro',
      'parsley', 'basil', 'ginger', 'fruit', 'salad', 'mango', 'pineapple', 'melon', 'watermelon', 'pear',
      'peach', 'pepper', 'pea',
      'maca', 'laranja', 'limao', 'uva', 'morango', 'abacate', 'tomate', 'batata', 'cebola', 'alho',
      'cenoura', 'alface', 'espinafre', 'brocolis', 'pepino', 'pimentao', 'cogumelo', 'abobrinha', 'salsa',
      'coentro', 'manjericao', 'gengibre', 'fruta', 'mamao', 'abacaxi', 'melancia', 'pera', 'pessego',
      'manga', 'rucula', 'couve', 'salada',
    ]),
  },
  bakery: {
    words: new Set([
      'bread', 'bagel', 'croissant', 'baguette', 'bun', 'tortilla', 'cake', 'muffin', 'roll',
      'pao', 'paes', 'bolo', 'torrada', 'broa',
    ]),
  },
  dairy: {
    words: new Set([
      'milk', 'cheese', 'butter', 'yogurt', 'yoghurt', 'cream', 'egg',
      'leite', 'queijo', 'manteiga', 'iogurte', 'creme', 'ovo', 'requeijao', 'nata',
    ]),
  },
  meat_fish: {
    words: new Set([
      'chicken', 'beef', 'pork', 'steak', 'bacon', 'ham', 'sausage', 'turkey', 'salmon', 'tuna', 'fish',
      'shrimp', 'meat', 'mince',
      'frango', 'carne', 'porco', 'bife', 'presunto', 'linguica', 'salsicha', 'peru', 'salmao', 'atum',
      'peixe', 'camarao', 'picanha', 'file',
    ]),
  },
  pantry: {
    words: new Set([
      'rice', 'pasta', 'spaghetti', 'flour', 'sugar', 'salt', 'oil', 'vinegar', 'bean', 'lentil',
      'cereal', 'oat', 'honey', 'jam', 'coffee', 'tea', 'sauce', 'ketchup', 'mustard', 'mayo',
      'mayonnaise', 'spice', 'soup', 'chocolate', 'cookie', 'cracker', 'chip', 'nut',
      'arroz', 'macarrao', 'farinha', 'acucar', 'sal', 'oleo', 'azeite', 'vinagre', 'feijao', 'lentilha',
      'aveia', 'mel', 'geleia', 'cafe', 'cha', 'molho', 'mostarda', 'maionese', 'biscoito', 'bolacha',
    ]),
    phrases: ['peanut butter', 'black pepper', 'olive oil', 'tomato sauce', 'molho de tomate'],
  },
  frozen: {
    words: new Set(['frozen', 'popsicle', 'sorvete', 'congelado', 'congelada', 'picole']),
    phrases: ['ice cream'],
  },
  drinks: {
    words: new Set([
      'water', 'juice', 'soda', 'beer', 'wine', 'coke', 'kombucha',
      'agua', 'suco', 'refrigerante', 'cerveja', 'vinho',
    ]),
  },
  household: {
    words: new Set([
      'detergent', 'sponge', 'trash', 'bleach', 'foil', 'napkin', 'battery', 'batterie', 'laundry',
      'detergente', 'esponja', 'lixo', 'sabao', 'amaciante', 'guardanapo', 'pilha',
    ]),
    phrases: [
      'dish soap', 'paper towel', 'toilet paper', 'trash bag', 'papel higienico', 'papel toalha',
      'saco de lixo', 'agua sanitaria',
    ],
  },
  personal_care: {
    words: new Set([
      'shampoo', 'conditioner', 'toothpaste', 'toothbrush', 'deodorant', 'soap', 'razor', 'lotion',
      'sunscreen', 'floss',
      'sabonete', 'desodorante', 'condicionador', 'protetor',
    ]),
    phrases: ['pasta de dente', 'escova de dente', 'fio dental'],
  },
}
