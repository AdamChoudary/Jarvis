import SwiftUI

/// Quick-Look style file inspector — slides up over the graph on node click.
struct SlateView: View {
    let title: String
    let path: String
    let color: Color
    let content: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title).font(Theme.serif(13, weight: .medium)).foregroundColor(Theme.ink)
                Spacer()
                Text(path).font(Theme.mono(10.5)).foregroundColor(Theme.inkDim)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.inkDim)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .magnetic(strength: 5)
            }
            .padding(14)
            Divider().overlay(Color.white.opacity(0.1))
            ScrollView {
                Text(content)
                    .font(Theme.mono(12))
                    .foregroundColor(Theme.inkDim)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        }
        .frame(maxWidth: 760, maxHeight: 380)
        .glassPanel()
    }
}
