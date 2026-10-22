import { describe, expect, it } from 'vitest'
import { guessCategory } from '../domain/categoryGuesser'
import { decide } from '../data/conflict'
import { timestampMicros } from '../data/rows'

describe('guessCategory', () => {
  it.each([
    ['Milk', 'dairy'],
    ['peanut butter', 'pantry'],
    ['Frozen peas', 'frozen'],
    ['Pão francês', 'bakery'],
    ['pasta de dente', 'personal_care'],
    ['Tomatoes', 'produce'],
    ['Papel higiênico', 'household'],
    ['Something odd', 'other'],
    ['', 'other'],
  ])('%s → %s', (name, category) => {
    expect(guessCategory(name)).toBe(category)
  })
})

describe('timestampMicros', () => {
  it('keeps microseconds that a Date would drop', () => {
    expect(timestampMicros('2026-10-22T12:00:00.123456+00:00') - timestampMicros('2026-10-22T12:00:00.123455+00:00')).toBe(1)
  })

  it('reads PostgREST and Postgres text formats as the same instant', () => {
    const a = timestampMicros('2026-10-22T12:00:00.1234+00:00')
    expect(timestampMicros('2026-10-22 12:00:00.1234+00')).toBe(a)
    expect(timestampMicros('2026-10-22T09:00:00.1234-03:00')).toBe(a)
    expect(timestampMicros('2026-10-22T12:00:00.123400Z')).toBe(a)
  })

  it('handles whole seconds', () => {
    expect(timestampMicros('2026-10-22T12:00:00+00:00')).toBe(Date.UTC(2026, 9, 22, 12) * 1000)
  })
})

describe('conflict resolution', () => {
  it('inserts unknown rows', () => expect(decide(undefined, 5)).toBe('insert'))
  it('protects pending local edits', () => expect(decide({ serverUs: 1, pending: true }, 9)).toBe('skip'))
  it('takes newer server rows', () => expect(decide({ serverUs: 1, pending: false }, 2)).toBe('overwrite'))
  it('skips echoes and stale events', () => {
    expect(decide({ serverUs: 2, pending: false }, 2)).toBe('skip')
    expect(decide({ serverUs: 3, pending: false }, 2)).toBe('skip')
  })
})
