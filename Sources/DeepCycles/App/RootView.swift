import SwiftUI
import DeepCyclesCore

/// The window: top bar, the page for the selected tab, Focus over it, the palette over everything.
@MainActor
struct RootView: View {
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var store: Store
    @EnvironmentObject var ui: AppState
    @EnvironmentObject var engine: CycleEngine

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                DateBar()
                ZStack {
                    Group {
                        switch ui.tab {
                        case .day: PlannerView()
                        case .week: WeekView()
                        case .systems: SystemsView()
                        }
                    }
                    if ui.focusMode {
                        FocusView().transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            if ui.showPalette {
                Color.black.opacity(0.18).ignoresSafeArea().onTapGesture { ui.showPalette = false }
                VStack { CommandPalette().padding(.top, 60); Spacer() }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: ui.showPalette)
        .animation(.easeInOut(duration: 0.22), value: ui.focusMode)
        .sheet(isPresented: $ui.showShutdown) {
            ShutdownView().environmentObject(store).environmentObject(ui).environmentObject(engine)
        }
        .background(Theme.paper)
        .onAppear { ui.appearance.apply() }
        .onChange(of: ui.appearance) { _, new in new.apply() }
        .task { await calendar.requestAccess() }
    }
}
