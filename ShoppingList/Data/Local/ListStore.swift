import Foundation
import Observation
import OSLog
import SwiftData

/// The only way the UI mutates data. Every method writes SwiftData and enqueues an outbox entry
/// in the same save, so the change is visible on the same frame and survives an app kill.
/// See docs/sync.md#writes-the-outbox.
@MainActor
@Observable
final class ListStore {
    @ObservationIgnored let context: ModelContext
    @ObservationIgnored let currentUserID: UUID
    @ObservationIgnored private let now: () -> Date
    /// Called after every local change; `SyncEngine` hooks in here to push the outbox.
    @ObservationIgnored var onLocalChange: () -> Void = {}

    init(context: ModelContext, currentUserID: UUID, now: @escaping () -> Date = { .now }) {
        self.context = context
        self.currentUserID = currentUserID
        self.now = now
    }

    // MARK: Lists

    /// The list the app opens into, creating "Groceries" on first launch.
    @discardableResult
    func ensureDefaultList() -> ListRecord {
        var descriptor = FetchDescriptor<ListRecord>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let list = ListRecord(name: String(localized: "Groceries"), createdBy: currentUserID, now: now())
        context.insert(list)
        enqueue(list)
        commit()
        return list
    }

    /// Soft-deletes a list (e.g. your own empty list after joining your partner's).
    func deleteList(_ list: ListRecord) {
        list.deletedAt = now()
        enqueue(list)
        commit()
    }

    /// Removes everything stored locally — used on sign-out so the next account starts clean.
    func wipeLocalData() {
        // Deletes object by object on purpose: batch `delete(model:)` bypasses objects already loaded
        // in the context, so the UI (and `ensureDefaultList`) would keep seeing the old account's rows.
        do {
            try context.fetch(FetchDescriptor<OutboxEntry>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<ItemRecord>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<ListRecord>()).forEach(context.delete)
            try context.save()
        } catch {
            Logger.store.error("Wipe failed: \(error)")
        }
    }

    // MARK: Items

    @discardableResult
    func addItem(named rawName: String, to list: ListRecord) -> ItemRecord? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let item = ItemRecord(
            listID: list.id,
            name: String(name.prefix(100)),
            category: CategoryGuesser.guess(name),
            position: Ordering.positionAtTop(of: activeItems(in: list.id).map(\.position)),
            createdBy: currentUserID,
            now: now()
        )
        context.insert(item)
        enqueue(item)
        commit()
        return item
    }

    func activeItemCount(in listID: UUID) -> Int {
        activeItems(in: listID).count
    }

    func setChecked(_ isChecked: Bool, for item: ItemRecord) {
        guard item.isChecked != isChecked else { return }
        item.isChecked = isChecked
        item.checkedBy = isChecked ? currentUserID : nil
        item.checkedAt = isChecked ? now() : nil
        touch(item)
    }

    func update(_ item: ItemRecord, name: String, quantity: String?, note: String?, category: Category) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        item.name = String(trimmedName.prefix(100))
        item.quantity = quantity?.nilIfBlank.map { String($0.prefix(40)) }
        item.note = note?.nilIfBlank.map { String($0.prefix(500)) }
        item.category = category
        touch(item)
    }

    /// Drops `item` between two neighbors (either may be nil at the edges of its section).
    func move(_ item: ItemRecord, between above: ItemRecord?, and below: ItemRecord?) {
        item.position = Ordering.position(between: above?.position, and: below?.position)
        item.updatedBy = currentUserID
        enqueue(item)

        let siblings = activeItems(in: item.listID).sorted { $0.position < $1.position }
        if Ordering.needsRenormalization(siblings.map(\.position)) {
            for (sibling, position) in zip(siblings, Ordering.renormalized(count: siblings.count)) {
                sibling.position = position
                sibling.updatedBy = currentUserID
                enqueue(sibling)
            }
        }
        commit()
    }

    func delete(_ item: ItemRecord) {
        item.deletedAt = now()
        touch(item)
    }

    /// Soft-deletes every checked item — the "done shopping" action.
    func clearChecked(in listID: UUID) {
        let checked = activeItems(in: listID).filter(\.isChecked)
        guard !checked.isEmpty else { return }
        let deletedAt = now()
        for item in checked {
            item.deletedAt = deletedAt
            item.updatedBy = currentUserID
            enqueue(item)
        }
        commit()
    }

    // MARK: Private

    private func touch(_ item: ItemRecord) {
        item.updatedBy = currentUserID
        enqueue(item)
        commit()
    }

    private func activeItems(in listID: UUID) -> [ItemRecord] {
        let descriptor = FetchDescriptor<ItemRecord>(
            predicate: #Predicate { $0.listID == listID && $0.deletedAt == nil }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func enqueue(_ item: ItemRecord) {
        item.hasPendingChanges = true
        enqueue(.item, rowID: item.id, dto: ItemDTO(item))
    }

    private func enqueue(_ list: ListRecord) {
        list.hasPendingChanges = true
        enqueue(.list, rowID: list.id, dto: ListDTO(list))
    }

    /// Coalesces: a row has at most one pending entry, holding its latest snapshot.
    private func enqueue(_ entity: OutboxEntity, rowID: UUID, dto: some Encodable) {
        let payload: Data
        do {
            payload = try JSONEncoder.outbox.encode(dto)
        } catch {
            Logger.store.error("Failed to encode \(entity.rawValue) \(rowID): \(error)")
            return
        }

        var descriptor = FetchDescriptor<OutboxEntry>(predicate: #Predicate { $0.rowID == rowID })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.payload = payload
            existing.attempts = 0
            existing.revision += 1
        } else {
            context.insert(OutboxEntry(entity: entity, rowID: rowID, payload: payload, now: now()))
        }
    }

    private func commit() {
        do {
            try context.save()
        } catch {
            Logger.store.error("Save failed: \(error)")
        }
        onLocalChange()
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
