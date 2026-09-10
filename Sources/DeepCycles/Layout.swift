import SwiftUI
import AppKit

// MARK: - Overlap packing

struct LanePlacement { var col: Int; var cols: Int }

/// Interval partitioning: overlapping items get side-by-side columns, like Calendar.app.
func packOverlaps(_ items: [TimeBlock]) -> [UUID: LanePlacement] {
    var result: [UUID: LanePlacement] = [:]
    let sorted = items.sorted { $0.start == $1.start ? $0.end > $1.end : $0.start < $1.start }
    var cluster: [(UUID, Int)] = []
    var columnEnds: [Date] = []
    var clusterEnd = Date.distantPast

    func flush() {
        for (id, col) in cluster { result[id] = LanePlacement(col: col, cols: max(1, columnEnds.count)) }
        cluster = []; columnEnds = []
    }

    for item in sorted {
        if item.start >= clusterEnd { flush(); clusterEnd = item.end }
        var col = columnEnds.firstIndex { $0 <= item.start }
        if let c = col { columnEnds[c] = item.end } else { columnEnds.append(item.end); col = columnEnds.count - 1 }
        cluster.append((item.id, col!))
        clusterEnd = max(clusterEnd, item.end)
    }
    flush()
    return result
}

// MARK: - Task list component

/// Checkbox rows with inline editing, delete on hover, and an always-present "add" row.
struct TaskList: View {
    @Binding var items: [TaskItem]
    var placeholder: String = "Add a task"
    var showDone: Bool = true
    var focusRequest: Int = 0
    @State private var newText = ""
    @FocusState private var focusedID: UUID?
    @FocusState private var addFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach($items) { $item in
                if showDone || !item.done {
                    TaskRow(item: $item, focused: $focusedID) { items.removeAll { $0.id == item.id } }
                }
            }
            HStack(spacing: Space.s) {
                Image(systemName: "plus").font(.system(size: 11, weight: .medium)).foregroundColor(Theme.inkFaint).frame(width: 16)
                TextField(placeholder, text: $newText)
                    .textFieldStyle(.plain).font(TypeScale.body)
                    .focused($addFocused)
                    .onSubmit { add() }
            }
            .padding(.vertical, 5).padding(.horizontal, Space.s)
        }
        .onChange(of: focusRequest) { addFocused = true }
    }

    private func add() {
        let t = newText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        items.append(TaskItem(text: t))
        newText = ""
        addFocused = true
    }
}

struct TaskRow: View {
    @Binding var item: TaskItem
    var focused: FocusState<UUID?>.Binding
    let onDelete: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: Space.s) {
            TaskCheck(done: $item.done)
            TextField("", text: $item.text)
                .textFieldStyle(.plain).font(TypeScale.body)
                .foregroundColor(item.done ? Theme.inkFaint : Theme.ink)
                .opacity(item.done ? 0.6 : 1)
                .focused(focused, equals: item.id)
            if hover {
                Button(action: onDelete) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundColor(Theme.inkFaint)
                }.buttonStyle(.plain)
            }
        }
        .padding(.vertical, 5).padding(.horizontal, Space.s)
        .background(hover ? Theme.paper.opacity(0.7) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
        .onHover { hover = $0 }
    }
}
