/**
 * Store sections, in list order (roughly a store walk). Values are stored in `items.category`
 * and shared with the iOS app (`Domain/Category.swift`) — never change them without a migration.
 */
export const categories = [
  'produce',
  'bakery',
  'dairy',
  'meat_fish',
  'pantry',
  'frozen',
  'drinks',
  'household',
  'personal_care',
  'other',
] as const

export type Category = (typeof categories)[number]

export function categoryFrom(stored: string): Category {
  return (categories as readonly string[]).includes(stored) ? (stored as Category) : 'other'
}

/** Name, symbol and tint per category; mirrors `DesignSystem/Category+Style.swift`. */
export const categoryStyle: Record<Category, { name: string; symbol: string; tint: string }> = {
  produce: { name: 'Produce', symbol: '🥕', tint: 'var(--green)' },
  bakery: { name: 'Bakery', symbol: '🥖', tint: 'var(--brown)' },
  dairy: { name: 'Dairy & Eggs', symbol: '🥛', tint: 'var(--cyan)' },
  meat_fish: { name: 'Meat & Fish', symbol: '🐟', tint: 'var(--red)' },
  pantry: { name: 'Pantry', symbol: '🥫', tint: 'var(--orange)' },
  frozen: { name: 'Frozen', symbol: '❄️', tint: 'var(--teal)' },
  drinks: { name: 'Drinks', symbol: '🍷', tint: 'var(--purple)' },
  household: { name: 'Household', symbol: '🏠', tint: 'var(--indigo)' },
  personal_care: { name: 'Personal Care', symbol: '🧴', tint: 'var(--pink)' },
  other: { name: 'Other', symbol: '🧺', tint: 'var(--gray)' },
}
