import SwiftUI

/// ⌘, — appearance, the hours a new day starts with, and calendar sync.
@MainActor
struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var calendar: CalendarService

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            section("Appearance") {
                SegmentPicker(selection: $store.appearance, options: Appearance.allCases.map { (value: $0, label: $0.label) })
                    .frame(width: 260)
            }

            section("Work day") {
                HStack(spacing: Space.l) {
                    ValueStepper($store.system.defaultWorkStartHour, in: 0...22) { "From \($0):00" }
                    ValueStepper($store.system.defaultWorkEndHour, in: 1...23) { "to \($0):00" }
                }
                Text("The grid a new day starts with. A single day is changed from the gear in the Day footer.")
                    .font(TypeScale.caption).foregroundColor(Theme.inkFaint)
            }

            section("Calendar") {
                if calendar.authorized {
                    Toggle("Sync blocks to the calendar automatically", isOn: $calendar.autoSync)
                        .toggleStyle(KeySwitchStyle())
                        .font(TypeScale.body)
                    Picker("Write to", selection: $calendar.targetCalendarID) {
                        ForEach(calendar.calendars.filter { $0.allowsContentModifications }, id: \.calendarIdentifier) { c in
                            Text(c.title).tag(c.calendarIdentifier)
                        }
                    }
                    .font(TypeScale.body)
                    if !calendar.calendars.contains(where: { $0.title == "Time Blocks" }) {
                        Button("Create a “Time Blocks” calendar") { calendar.createTimeBlocksCalendar() }.buttonStyle(QuietButtonStyle())
                    }
                    if let on = calendar.createdOn {
                        Text("“Time Blocks” created on \(on).").font(TypeScale.caption).foregroundColor(Theme.breakC)
                    }
                    if let err = calendar.lastError {
                        Text(err).font(TypeScale.caption).foregroundColor(Theme.nowLine).fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(calendar.lastError ?? "Requesting calendar access…").font(TypeScale.caption).foregroundColor(Theme.inkFaint)
                    Button("Retry access") { Task { await calendar.requestAccess() } }.buttonStyle(QuietButtonStyle())
                }
            }
        }
        .padding(Space.xl)
        .frame(width: 460)
        .background(Theme.paper)
        .onChange(of: store.system.defaultWorkStartHour) {
            if store.system.defaultWorkEndHour <= store.system.defaultWorkStartHour {
                store.system.defaultWorkEndHour = min(23, store.system.defaultWorkStartHour + 1)
            }
        }
        .onChange(of: store.system.defaultWorkEndHour) {
            if store.system.defaultWorkStartHour >= store.system.defaultWorkEndHour {
                store.system.defaultWorkStartHour = max(0, store.system.defaultWorkEndHour - 1)
            }
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(title).font(TypeScale.title).foregroundColor(Theme.ink)
            content()
        }
    }
}
