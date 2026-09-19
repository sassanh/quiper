import SwiftUI

/// Shared editor content for one routing rule: the regex pattern field and the
/// action picker. Both targets render the exact same controls (same placeholder,
/// same `RoutingAction` options) so the rule editor can never drift between
/// platforms. Platform-specific decorations—macOS's reorder chevrons and the
/// iOS swipe-to-delete/Edit-mode affordances—wrap this component per target.
struct RoutingRuleField: View {
    @Binding var rule: RoutingRule
    let ruleID: UUID
    let focusedRuleID: FocusState<UUID?>.Binding
    /// Pinned-tab engines never navigate in place, so their editor offers
    /// only popup and external actions.
    var allowedActions: [RoutingAction]? = nil

    private var visibleActions: [RoutingAction] {
        guard let allowedActions else { return RoutingAction.allCases }
        // Existing rules keep their stored action visible instead of being
        // silently rewritten; the routing gate maps in-place stays to popups
        // for pinned-tab engines at runtime.
        if allowedActions.contains(rule.action) {
            return allowedActions
        }
        return allowedActions + [rule.action]
    }

    var body: some View {
        HStack(spacing: 10) {
            TextField("e.g. ^https?://([^/]*\\.)?google\\.com", text: $rule.pattern)
                .focused(focusedRuleID, equals: ruleID)
                #if os(macOS)
                .textFieldStyle(.roundedBorder)
                .fontDesign(.monospaced)
                .frame(maxWidth: .infinity)
                #else
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .fontDesign(.monospaced)
                #endif
            Picker("Action", selection: $rule.action) {
                ForEach(visibleActions) { action in
                    Text(action.rawValue).tag(action)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            // Wide enough for the longest action name plus the menu chevron;
            // bump when adding `RoutingAction` cases so the value never
            // truncates.
            .frame(width: 120)
            .accessibilityLabel("Action")
        }
    }
}
