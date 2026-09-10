import SwiftUI

/// Typography-only logo: "deep" set bold, "cycles" set light, and the full stop
/// drawn as an open ring — a timer that hasn't closed yet.
struct Wordmark: View {
    var size: CGFloat = 16
    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Text("deep").font(.system(size: size, weight: .bold, design: .serif)).foregroundColor(Theme.ink)
            Text("cycles").font(.system(size: size, weight: .light, design: .serif)).foregroundColor(Theme.ink)
            Circle().trim(from: 0.15, to: 1)
                .stroke(Theme.deep, style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: size * 0.3, height: size * 0.3)
                .padding(.leading, size * 0.12)
                .alignmentGuide(.lastTextBaseline) { d in d[.bottom] }
        }
        .fixedSize()
        .accessibilityLabel("DeepCycles")
    }
}
