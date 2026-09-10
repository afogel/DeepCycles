import Foundation

/// Which column of how many an item takes when it overlaps its neighbours.
package struct LanePlacement: Equatable {
    package var col: Int
    package var cols: Int

    package init(col: Int, cols: Int) {
        self.col = col
        self.cols = cols
    }
}

/// Interval partitioning: overlapping items get side-by-side columns, like Calendar.app.
/// Items that don't touch each other all get a single full-width column.
package func packOverlaps(_ items: [TimeBlock]) -> [UUID: LanePlacement] {
    var result: [UUID: LanePlacement] = [:]
    let sorted = items.sorted { $0.start == $1.start ? $0.end > $1.end : $0.start < $1.start }
    var cluster: [(UUID, Int)] = []
    var columnEnds: [Date] = []
    var clusterEnd = Date.distantPast

    func flush() {
        for (id, col) in cluster { result[id] = LanePlacement(col: col, cols: max(1, columnEnds.count)) }
        cluster = []
        columnEnds = []
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
