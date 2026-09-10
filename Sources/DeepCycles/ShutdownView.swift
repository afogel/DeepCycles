import SwiftUI

@MainActor
struct ShutdownView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var engine: CycleEngine

    private var loggedDeepMinutes: Int { store.today.sessions.reduce(0) { $0 + $1.deepMinutes } }
    private var plannedDeepMinutes: Int { store.today.blocks.filter { $0.kind == .deep }.reduce(0) { $0 + $1.minutes } }
    private var cyclesHit: (Int, Int) {
        let all = store.today.sessions.flatMap { $0.cycles }.filter { !$0.completed.isEmpty }
        return (all.filter { $0.completed == "Yes" }.count, all.count)
    }

    var body: some View {
        VStack(spacing: 0) {
        HStack {
            Text("End of day").font(Theme.display(22)).foregroundColor(Theme.ink)
            Text(store.selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(Theme.body).foregroundColor(Theme.inkFaint)
            Spacer()
            Button("Close  ⎋") { store.showShutdown = false }.buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 28).padding(.vertical, 16)
        Divider()
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Daily metrics").font(Theme.display(24)).foregroundColor(Theme.ink)
                Text("Record the behaviours that matter. Writing a zero here is the nudge that keeps tomorrow honest.")
                    .foregroundColor(Theme.inkFaint)

                HStack(spacing: 12) {
                    stat("deep work, from cycles", hours(loggedDeepMinutes), Theme.deep)
                    stat("deep work, planned", hours(plannedDeepMinutes), Theme.deep.opacity(0.55))
                    stat("cycle targets hit", "\(cyclesHit.0) of \(cyclesHit.1)", Theme.breakC)
                    stat("blocks planned", "\(store.today.blocks.count)", Theme.tasks)
                }

                if !store.system.disciplines.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SectionHeading("Disciplines")
                            Spacer()
                            Button("Edit list") { store.showShutdown = false; store.tab = 2 }.buttonStyle(QuietButtonStyle())
                        }
                        ForEach(store.system.disciplines) { d in disciplineRow(d) }
                    }
                    .panel()
                }

                VStack(spacing: 8) {
                    ForEach($store.today.metrics) { $m in
                        HStack(spacing: 10) {
                            TextField("Metric, e.g. CC for cold calls", text: $m.name)
                                .textFieldStyle(.plain).font(Theme.body)
                                .padding(8).background(Theme.paper).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            TextField("0", text: $m.value)
                                .textFieldStyle(.plain).font(Theme.display(18)).multilineTextAlignment(.trailing)
                                .padding(8).frame(width: 90).background(Theme.paper).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            Button { store.today.metrics.removeAll { $0.id == m.id } } label: {
                                Image(systemName: "xmark").font(.system(size: 10)).foregroundColor(Theme.inkFaint)
                            }.buttonStyle(.borderless)
                        }
                    }
                    HStack {
                        Button { store.today.metrics.append(Metric(name: "", value: "")) } label: { Label("Add metric", systemImage: "plus") }
                            .buttonStyle(QuietButtonStyle())
                        Button("Fill DW from cycles") {
                            if let i = store.today.metrics.firstIndex(where: { $0.name.hasPrefix("DW") }) {
                                store.today.metrics[i].value = String(format: "%.1f", Double(loggedDeepMinutes) / 60)
                            } else {
                                store.today.metrics.append(Metric(name: "DW (deep work hrs)", value: String(format: "%.1f", Double(loggedDeepMinutes) / 60)))
                            }
                        }.buttonStyle(QuietButtonStyle())
                        Spacer()
                    }
                }
                .panel()

                Text("Shutdown ritual").font(Theme.display(24)).foregroundColor(Theme.ink).padding(.top, 8)
                VStack(alignment: .leading, spacing: 10) {
                    let pendingCapture = store.today.captured.contains { !$0.done }
                    HStack(alignment: .top) {
                        check(pendingCapture ? "Full capture: the Collection box still has notes in it." : "Full capture: the Collection box is empty.", done: !pendingCapture)
                        Spacer()
                        if pendingCapture {
                            Button("Move to Tasks") { store.processCollection() }.buttonStyle(QuietButtonStyle())
                        }
                    }
                    if pendingCapture {
                        TaskList(items: $store.today.captured, placeholder: "Add another").padding(.leading, Space.l)
                    }
                    let tomorrow = store.plan(for: Calendar.current.date(byAdding: .day, value: 1, to: store.selectedDate) ?? store.selectedDate)
                    let tomorrowDeep = tomorrow.blocks.contains { $0.kind == .deep }
                    check(tomorrowDeep ? "Tomorrow has a deep-work block." : "Tomorrow has no deep-work block yet (⌘] to plan it).", done: tomorrowDeep)
                    let undebriefed = store.today.sessions.filter { !$0.finished }.count
                    check(undebriefed == 0 ? "Every cycle session is debriefed." : "\(undebriefed) cycle session\(undebriefed == 1 ? "" : "s") not yet debriefed.", done: undebriefed == 0)
                    let logged = store.system.disciplines.allSatisfy { !(store.today.disciplineLog[$0.id.uuidString] ?? "").isEmpty }
                    check(logged ? "Disciplines are logged." : "Some disciplines aren't logged yet.", done: logged)
                }
                .panel()

                HStack(spacing: 14) {
                    Toggle("", isOn: shutdownComplete).toggleStyle(KeySwitchStyle()).labelsHidden()
                    Text("Shutdown complete").font(Theme.display(20)).foregroundColor(store.today.shutdownComplete ? Theme.breakC : Theme.ink)
                }

                if store.today.shutdownComplete {
                    Text("Done for the day. When work anxiety shows up tonight: you checked the box. Close the planner.")
                        .foregroundColor(Theme.inkFaint)
                    Button("Close the planner") { store.showShutdown = false }.buttonStyle(InkButtonStyle(fill: Theme.breakC))
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        }
        .frame(width: 780, height: 720)
        .background(Theme.paper)
        .onExitCommand { store.showShutdown = false }
    }

    /// Flipping the switch stops a running timer; merely opening the sheet on a completed day does not.
    private var shutdownComplete: Binding<Bool> {
        Binding(get: { store.today.shutdownComplete }, set: { done in
            store.today.shutdownComplete = done
            if done { engine.stop() }
        })
    }

    private func hours(_ minutes: Int) -> String {
        minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(Theme.display(28).monospacedDigit()).foregroundColor(color)
            Text(label).font(Theme.small).foregroundColor(Theme.inkFaint)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paperDeep)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func check(_ text: String, done: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: done ? "checkmark.square.fill" : "square")
                .foregroundColor(done ? Theme.breakC : Theme.inkFaint).padding(.top, 2)
            Text(text).font(Theme.body).foregroundColor(done ? Theme.inkFaint : Theme.ink)
        }
    }

    private func disciplineRow(_ d: Discipline) -> some View {
        let key = d.id.uuidString
        let value = Binding<String>(
            get: { store.today.disciplineLog[key] ?? "" },
            set: { store.today.disciplineLog[key] = $0 }
        )
        return HStack(spacing: 12) {
            Text(d.code).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundColor(Theme.deep).frame(width: 40, alignment: .leading)
            Text(d.name).font(Theme.body).foregroundColor(Theme.ink)
            Spacer()
            if d.isNumber {
                if d.code.uppercased() == "DW" {
                    Button("from cycles") { value.wrappedValue = String(format: "%.1f", Double(loggedDeepMinutes) / 60) }
                        .buttonStyle(QuietButtonStyle())
                }
                TextField("0", text: value)
                    .textFieldStyle(.plain).font(Theme.display(18)).multilineTextAlignment(.trailing)
                    .padding(6).frame(width: 70).background(Theme.paper).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                if !d.target.isEmpty { Text("/ \(d.target)").font(Theme.small).foregroundColor(Theme.inkFaint) }
            } else {
                Toggle("", isOn: Binding(get: { value.wrappedValue == "1" }, set: { value.wrappedValue = $0 ? "1" : "0" }))
                    .toggleStyle(KeySwitchStyle()).labelsHidden()
            }
        }
    }
}
