import SwiftUI

struct LicensesView: View {
    @State private var licenseText: String = ""
    @State private var noticesText: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Third-Party Notices")
                    .font(.headline)
                Text(noticesText.isEmpty ? "Missing THIRD_PARTY_NOTICES.txt in app bundle." : noticesText)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)

                Divider()

                Text("GPL-3.0 License")
                    .font(.headline)
                Text(licenseText.isEmpty ? "Missing LICENSE.txt in app bundle." : licenseText)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding()
        }
        .navigationTitle("Licenses")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Load bundled texts (see Clauntty/Resources/Licenses).
            noticesText = loadResourceText(name: "THIRD_PARTY_NOTICES", ext: "txt")
            licenseText = loadResourceText(name: "LICENSE", ext: "txt")
        }
    }

    private func loadResourceText(name: String, ext: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Licenses") else {
            return ""
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}

#Preview {
    NavigationStack {
        LicensesView()
    }
}

