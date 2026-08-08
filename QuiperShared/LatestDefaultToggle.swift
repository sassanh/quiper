import SwiftUI

/// "Use Latest Default" switch shared by both targets. Turning it on makes the
/// paired editor read-only and keeps the content in sync with Quiper's bundled
/// default; turning it off hands control back to the user's editable copy.
struct LatestDefaultToggle: View {
    var isInSync: Bool
    var syncedDescription: String
    var customDescription: String
    var setInSync: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Use Latest Default")
                    .font(.body)
                Text(isInSync ? syncedDescription : customDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: Binding(
                get: { isInSync },
                set: { setInSync($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .frame(width: 112, height: 32, alignment: .topTrailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
