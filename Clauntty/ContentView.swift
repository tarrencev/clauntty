import SwiftUI

struct ContentView: View {
    @EnvironmentObject var connectionStore: ConnectionStore
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            switch appState.connectionStatus {
            case .connected:
                TerminalView()
            default:
                ConnectionListView()
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ConnectionStore())
        .environmentObject(AppState())
}
