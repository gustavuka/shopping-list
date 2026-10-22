import { useState, type FormEvent } from 'react'
import { categories, categoryFrom, categoryStyle, type Category } from '../domain/category'
import type { ItemRow } from '../data/rows'
import { haptic } from '../ui/haptics'
import { Sheet } from '../ui/Sheet'
import { useSession } from './session'

/** Edit name, quantity, note and category. Port of `ItemEditorSheet.swift`. */
export function ItemEditor({ item, onClose }: { item: ItemRow; onClose: () => void }) {
  const { store } = useSession()
  const [name, setName] = useState(item.name)
  const [quantity, setQuantity] = useState(item.quantity ?? '')
  const [note, setNote] = useState(item.note ?? '')
  const [category, setCategory] = useState<Category>(categoryFrom(item.category))

  function save(event: FormEvent) {
    event.preventDefault()
    if (!name.trim()) return
    void store.update(item.id, { name, quantity, note, category })
    onClose()
  }

  return (
    <Sheet title="Edit item" onClose={onClose}>
      <form className="form" onSubmit={save}>
        <input className="field" aria-label="Name" maxLength={100} value={name} onChange={(e) => setName(e.target.value)} />
        <input
          className="field"
          placeholder="Quantity (e.g. 2, 500 g)"
          aria-label="Quantity"
          maxLength={40}
          value={quantity}
          onChange={(e) => setQuantity(e.target.value)}
        />
        <textarea
          className="field"
          placeholder="Note"
          aria-label="Note"
          maxLength={500}
          rows={2}
          value={note}
          onChange={(e) => setNote(e.target.value)}
        />
        <select className="field" aria-label="Category" value={category} onChange={(e) => setCategory(e.target.value as Category)}>
          {categories.map((c) => (
            <option key={c} value={c}>
              {categoryStyle[c].symbol} {categoryStyle[c].name}
            </option>
          ))}
        </select>
        <button type="submit" className="button prominent" disabled={!name.trim()}>
          Save
        </button>
        <button
          type="button"
          className="button destructive"
          onClick={() => {
            haptic('rigid')
            void store.delete(item.id)
            onClose()
          }}
        >
          Delete
        </button>
      </form>
    </Sheet>
  )
}
