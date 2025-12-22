import SwiftUI
import os.log

struct TerminalView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var ghosttyApp: GhosttyApp

    var body: some View {
        ZStack {
            // Show terminal surface based on GhosttyApp readiness
            switch ghosttyApp.readiness {
            case .loading:
                Color.black
                    .ignoresSafeArea()
                VStack {
                    ProgressView()
                        .tint(.white)
                    Text("Initializing terminal...")
                        .foregroundColor(.gray)
                        .padding(.top)
                }

            case .error:
                Color.black
                    .ignoresSafeArea()
                VStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                        .font(.largeTitle)
                    Text("Failed to initialize terminal")
                        .foregroundColor(.white)
                        .padding(.top)
                }

            case .ready:
                TerminalSurface(ghosttyApp: ghosttyApp)
                    .ignoresSafeArea()
                    .onAppear {
                        Logger.clauntty.info("TerminalView displayed with TerminalSurface")
                    }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    disconnect()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color.black.opacity(0.8), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func disconnect() {
        appState.connectionStatus = .disconnected
        appState.currentConnection = nil
        appState.activeSession = nil
    }
}

#Preview {
    NavigationStack {
        TerminalView()
            .environmentObject({
                let state = AppState()
                state.currentConnection = SavedConnection(
                    name: "Test Server",
                    host: "example.com",
                    username: "user",
                    authMethod: .password
                )
                state.connectionStatus = .connected
                return state
            }())
            .environmentObject(GhosttyApp())
    }
}
