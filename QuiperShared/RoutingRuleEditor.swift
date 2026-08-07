import SwiftUI

/// Shared editor content for one routing rule: the regex pattern field and the
/// action picker. Both targets render the exact same controls (same placeholder,
/// same `RoutingAction` options) so the rule editor can never drift between
/// platforms. Platform-specific decorations—macOS's reorder chevrons and the
/// iOS swipe-to-delete/Edit-mode affordances—wrap this component per target.
struct RoutingRuleField: View {
    @Binding var rule: RoutingRule

    var body: some View {
        HStack(spacing: 8) {
            TextField("e.g. ^https?://([^/]*\\.)?google\\.com", text: $rule.pattern)
                #if os(macOS)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                #else
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .fontDesign(.monospaced)
                #endif
            Picker("Action", selection: $rule.action) {
                ForEach(RoutingAction.allCases) { action in
                    Text(action.rawValue).tag(action)
                }
            }
            .pickerStyle(.menu)
            #if os(macOS)
            .frame(width: 90)
            #else
            .labelsHidden()
            .fixedSize()
            #endif
        }
    }
}
