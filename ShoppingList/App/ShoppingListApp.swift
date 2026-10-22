import SwiftData
import SwiftUI

@main
struct ShoppingListApp: App {
    // Keep init cheap: open the store, build services. Nothing waits on the network here
    // (docs/performance.md#launch).
    @State private var model: AppModel

    init() {
        LaunchTimer.appDidStart()
        let arguments = ProcessInfo.processInfo.arguments
        let isDemo = arguments.contains("-uiTesting")
        let container: ModelContainer
        do {
            container = try .app(inMemory: isDemo)
        } catch {
            fatalError("Could not open the local database: \(error)")
        }
        let model = isDemo
            ? AppModel(demoContainer: container, seeded: arguments.contains("-seeded"))
            : AppModel(container: container, config: .current)
        _model = State(initialValue: model)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .fontDesign(.rounded)
                .environment(model)
                .environment(model.network)
        }
        .modelContainer(model.container)
    }
}

/// Picks the welcome screen or the signed-in experience. A returning user goes straight to their list.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let session = model.session {
                SessionRootView()
                    .environment(session.store)
                    .environment(session.sync)
                    .id(session.userID)
                    .transition(.opacity)
            } else if let auth = model.auth {
                WelcomeView(auth: auth)
                    .transition(.opacity)
            } else {
                ContentUnavailableView(
                    "Supabase isn't configured",
                    systemImage: "wrench.and.screwdriver",
                    description: Text("Add SUPABASE_URL and SUPABASE_KEY to Config/Secrets.xcconfig. See docs/setup.md.")
                )
            }
        }
        .animation(.smooth, value: model.session?.userID)
        .onOpenURL { model.handle($0) }
    }
}
