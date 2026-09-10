/// Linear undo / redo over snapshots of some state, keeping the last `limit` of them.
package struct UndoHistory<Snapshot> {
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    package let limit: Int

    package init(limit: Int = 50) { self.limit = limit }

    package var canUndo: Bool { !undoStack.isEmpty }
    package var canRedo: Bool { !redoStack.isEmpty }

    /// Call before a change, with the state as it is now. Anything redoable is forgotten.
    package mutating func record(_ snapshot: Snapshot) {
        undoStack.append(snapshot)
        if undoStack.count > limit { undoStack.removeFirst(undoStack.count - limit) }
        redoStack.removeAll()
    }

    /// The snapshot to restore, or nil when there is nothing to undo. `current` captures the
    /// present state of the same place, so the change can be redone.
    package mutating func undo(current: (Snapshot) -> Snapshot) -> Snapshot? {
        guard let s = undoStack.popLast() else { return nil }
        redoStack.append(current(s))
        return s
    }

    package mutating func redo(current: (Snapshot) -> Snapshot) -> Snapshot? {
        guard let s = redoStack.popLast() else { return nil }
        undoStack.append(current(s))
        return s
    }
}
