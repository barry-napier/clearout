import SwiftUI

/// The first-run walk-through: what Clearout does, and the one permission it wants.
struct WelcomeView: View {
    let state: AppState
    let finish: () -> Void
    @State private var step = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                ForEach(0..<2) { index in
                    Circle()
                        .fill(index <= step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            if step == 0 { hello } else { access }
        }
        .padding(28)
        .frame(width: 520, height: 390, alignment: .topLeading)
    }

    private var hello: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                Text("Welcome to Clearout").font(.largeTitle.bold())
            }
            Text("See what fills your Mac. Then clean it up.").font(.title3)
            Label("Looking does not change anything.", systemImage: "eye")
            Label("It only moves things to the Trash. You pick them first.", systemImage: "trash")
            Label("It cannot make iCloud download your files.", systemImage: "icloud.slash")
            Label("Nothing leaves your Mac.", systemImage: "lock")
            Spacer()
            HStack {
                Spacer()
                Button("Get Started") { step = 1 }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var access: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("One permission").font(.title.bold())
            Text("Full Disk Access lets Clearout see every folder. Without it, your Mac hides some and asks you again and again.")
                .fixedSize(horizontal: false, vertical: true)
            Text(state.hasFullAccess ? "🟢 Full Disk Access is on" : "🟡 Full Disk Access is not on yet")
                .font(.headline)
            if !state.hasFullAccess {
                Button("Open System Settings") { Permissions.openFullDiskAccessSettings() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Text("Switch Clearout on. If it is not in the list, click + and pick it from Applications. If your Mac says Quit & Reopen, click that.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            HStack {
                Spacer()
                Button(state.hasFullAccess ? "Open Clearout" : "Continue Without It", action: finish)
                    .keyboardShortcut(state.hasFullAccess ? .defaultAction : nil)
            }
        }
    }
}
