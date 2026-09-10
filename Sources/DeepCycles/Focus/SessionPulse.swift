import SwiftUI
import DeepCyclesCore

// MARK: - Session pulse: energy and morale stacked on one axis, targets underneath

/// Two 1–5 lanes (energy, morale) that share the cycle axis, with target dots
/// under the same columns. `compact` is the sidebar version.
struct SessionPulse: View {
    let session: CycleSession
    var tall: Bool = false
    var compact: Bool = false

    private func rated(_ i: Int) -> Bool {
        i < session.cycles.count && (i <= session.currentCycle || session.cycles[i].completed != nil)
    }
    private var energy: [Int?] { (0..<session.cycleCount).map { rated($0) ? session.cycles[$0].energy : nil } }
    private var morale: [Int?] { (0..<session.cycleCount).map { rated($0) ? session.cycles[$0].morale : nil } }
    private var laneHeight: CGFloat { compact ? 18 : (tall ? 48 : 30) }
    private var labelWidth: CGFloat { compact ? 14 : 52 }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 6) {
            lane(compact ? "E" : "Energy", values: energy, color: Theme.deep)
            lane(compact ? "M" : "Morale", values: morale, color: Theme.tasks)
            HStack(spacing: Space.s) {
                Text(compact ? "" : "Target").font(TypeScale.caption).foregroundColor(Theme.inkFaint).frame(width: labelWidth, alignment: .leading)
                targetsRow
            }
            if !compact { axis }
        }
    }

    private func lane(_ label: String, values: [Int?], color: Color) -> some View {
        HStack(spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(label).font(TypeScale.caption).foregroundColor(Theme.inkFaint)
                if !compact, let v = values.compactMap({ $0 }).last {
                    Text("\(v)").font(TypeScale.caption.weight(.semibold).monospacedDigit()).foregroundColor(color)
                }
            }
            .frame(width: labelWidth, alignment: .leading)
            Sparkline(values: values, color: color, current: session.currentCycle)
                .frame(height: laneHeight)
        }
    }

    /// Dots on the same columns as the sparkline points.
    private var targetsRow: some View {
        GeometryReader { geo in
            let n = max(session.cycleCount, 2)
            let stepX = geo.size.width / CGFloat(n - 1)
            ForEach(0..<session.cycleCount, id: \.self) { i in
                let c = i < session.cycles.count ? session.cycles[i].completed : nil
                Circle()
                    .fill(Self.color(for: c))
                    .frame(width: compact ? 6 : 9, height: compact ? 6 : 9)
                    .position(x: CGFloat(i) * stepX, y: geo.size.height / 2)
            }
        }
        .frame(height: compact ? 8 : 12)
    }

    static func color(for outcome: TargetOutcome?) -> Color {
        switch outcome {
        case .yes: return Theme.breakC
        case .half: return Theme.tasks
        case .no: return Theme.nowLine
        case nil: return Theme.ruleFaint
        }
    }

    private var axis: some View {
        HStack(spacing: Space.s) {
            Color.clear.frame(width: labelWidth, height: 1)
            GeometryReader { geo in
                let n = max(session.cycleCount, 2)
                let stepX = geo.size.width / CGFloat(n - 1)
                ForEach(0..<session.cycleCount, id: \.self) { i in
                    Text("\(i + 1)")
                        .font(.system(size: 10, weight: i == session.currentCycle ? .semibold : .regular, design: .serif))
                        .foregroundColor(i == session.currentCycle ? Theme.ink : Theme.inkFaint)
                        .position(x: CGFloat(i) * stepX, y: 6)
                }
            }
            .frame(height: 12)
        }
    }
}

/// A 1–5 sparkline. Gaps in `values` (nil) break the line; the current cycle gets a ring.
struct Sparkline: View {
    let values: [Int?]
    let color: Color
    var current: Int = -1
    var maxValue: Double = 5

    var body: some View {
        Canvas { ctx, size in
            let n = max(values.count, 2)
            let stepX = size.width / CGFloat(n - 1)
            let pad: CGFloat = 4
            func point(_ i: Int, _ v: Int) -> CGPoint {
                CGPoint(x: CGFloat(i) * stepX,
                        y: pad + (size.height - 2 * pad) * (1 - CGFloat((Double(v) - 1) / (maxValue - 1))))
            }
            // baseline at 3 (neutral)
            var base = Path()
            let midY = pad + (size.height - 2 * pad) * 0.5
            base.move(to: CGPoint(x: 0, y: midY)); base.addLine(to: CGPoint(x: size.width, y: midY))
            ctx.stroke(base, with: .color(Theme.ruleFaint), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            // line
            var path = Path()
            var pen = false
            for (i, v) in values.enumerated() {
                if let v {
                    let p = point(i, v)
                    if pen { path.addLine(to: p) } else { path.move(to: p); pen = true }
                } else { pen = false }
            }
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            // dots
            for (i, v) in values.enumerated() {
                guard let v else { continue }
                let p = point(i, v)
                let r: CGFloat = i == current ? 3.5 : 2.5
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
                if i == current {
                    ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)), with: .color(color.opacity(0.5)), lineWidth: 1)
                }
            }
        }
    }
}
