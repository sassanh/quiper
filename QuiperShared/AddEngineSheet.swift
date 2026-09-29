import SwiftUI

/// Shared sheet for adding engines. The Blank tile creates an empty engine
/// immediately; bundled templates are grouped into Cloud and Local sections
/// and stay selectable so one confirmation can add several engines at once.
/// Templates whose engine is already in the list are marked Added; confirming
/// a selection containing them warns before creating duplicates.
struct AddEngineSheet: View {
    let templates: [Service]
    /// Engines already in the user's list. Their templates stay selectable but
    /// are marked Added so duplicate picks are visible before confirming.
    let existingEngines: [Service]
    let onAddBlank: () -> Void
    let onAddTemplates: ([Service]) -> Void
    let onCancel: () -> Void

    @ObservedObject private var iconStore = EngineTemplateIconStore.shared
    @State private var selectedTemplateNames: Set<String> = []
    @State private var selectionAnchorName: String?
    @State private var pendingSelection: [Service] = []
    @State private var showingDuplicateWarning = false

    /// Templates not yet in the user's list — what Select All Not Added picks.
    private var availableTemplates: [Service] {
        templates.filter { !isAlreadyAdded($0) }
    }

    private var cloudTemplates: [Service] {
        templates.filter { !DefaultEngineDefinitions.isLocalTemplate($0) }
    }

    private var localTemplates: [Service] {
        templates.filter { DefaultEngineDefinitions.isLocalTemplate($0) }
    }

    /// Templates in the order they are displayed, which is the order
    /// Shift-click ranges follow.
    private var displayedTemplates: [Service] {
        cloudTemplates + localTemplates
    }

    /// Whether the user already has an engine with this template's name.
    private func isAlreadyAdded(_ template: Service) -> Bool {
        existingEngines.contains { Self.nameKey($0.name) == Self.nameKey(template.name) }
    }

    private var allRemainingSelected: Bool {
        availableTemplates.allSatisfy { selectedTemplateNames.contains($0.name) }
    }

    private static func nameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    blankRow
                    if !cloudTemplates.isEmpty {
                        sectionHeader("Cloud")
                        templateGrid(cloudTemplates)
                    }
                    if !localTemplates.isEmpty {
                        sectionHeader("Local")
                        templateGrid(localTemplates)
                    }
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .modifier(SheetSizing())
        .background(sheetBackground)
        .task {
            iconStore.loadIcons(for: templates)
        }
        .alert("Add duplicate engines?", isPresented: $showingDuplicateWarning) {
            Button("Cancel", role: .cancel) { }
            Button("Add Duplicates") { onAddTemplates(pendingSelection) }
        } message: {
            Text(duplicateWarningMessage)
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.square")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
            Text("Add Engines")
                .font(.title3.bold())
            Spacer()
            Button("Select All Not Added") {
                selectedTemplateNames.formUnion(availableTemplates.map(\.name))
            }
            .disabled(allRemainingSelected)
            .accessibilityIdentifier("AddEngineSelectNotAdded")
            Button("Clear") {
                selectedTemplateNames.removeAll()
                selectionAnchorName = nil
            }
            .disabled(selectedTemplateNames.isEmpty)
            .accessibilityIdentifier("AddEngineClear")
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 96, maximum: 120), spacing: 12)]
    }

    private func templateGrid(_ items: [Service]) -> some View {
        LazyVGrid(columns: gridColumns, spacing: 12) {
            ForEach(items) { template in
                templateTile(template)
            }
        }
    }

    // MARK: - Tiles

    /// The Blank tile sits in the same grid track as template tiles so it lines
    /// up with the columns below it.
    private var blankRow: some View {
        LazyVGrid(columns: gridColumns, spacing: 12) {
            blankTile
        }
    }

    private var blankTile: some View {
        Button(action: onAddBlank) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            Color.secondary,
                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                        )
                        .frame(width: 64, height: 64)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.secondary.opacity(0.10))
                        )
                    Image(systemName: "plus")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                }
                .frame(height: 64)
                Text("Blank")
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(tileBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tileBorder, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("AddEngineBlank")
    }

    /// The template with its cached favicon applied, so the tile shows the icon
    /// the moment the download finishes and the globe placeholder until then.
    private func displayTemplate(_ template: Service) -> Service {
        var copy = template
        copy.iconBase64 = iconStore.icon(for: template)
        return copy
    }

    private func templateTile(_ template: Service) -> some View {
        let added = isAlreadyAdded(template)
        let isSelected = selectedTemplateNames.contains(template.name)
        let fill = isSelected ? Color.secondary.opacity(0.10) : tileBackground
        return Button {
            handleTileSelection(of: template)
        } label: {
            VStack(spacing: 8) {
                EngineIconView(service: displayTemplate(template), size: 64)
                    .frame(width: 64, height: 64)
                Text(template.name)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Group {
                    if added {
                        Text("Added")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background {
                                Capsule().fill(Color.secondary.opacity(0.12))
                                Capsule().stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
                            }
                    } else {
                        Color.clear
                    }
                }
                .frame(height: 16)
            }
            // Reserves the checkmark band (8pt inset + 18pt badge) so the
            // selection badge clears the icon; it mirrors the 8pt side inset.
            .padding(.top, 26)
            .padding(.bottom, 12)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.secondary : tileBorder, lineWidth: isSelected ? 1.5 : 0.5)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(fill))
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("AddEngineTemplate-\(template.name)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// One selection interaction. On macOS a plain click picks just this tile,
    /// Cmd-click toggles it, and Shift-click selects the range from the anchor
    /// tile; on iOS a tap toggles, the standard gesture for multi-select grids
    /// without modifier keys.
    private func handleTileSelection(of template: Service) {
        #if os(macOS)
        let isToggle = NSEvent.modifierFlags.contains(.command)
        let isRange = NSEvent.modifierFlags.contains(.shift)

        let displayedNames = displayedTemplates.map(\.name)
        if isRange,
           let anchor = selectionAnchorName,
           let anchorIndex = displayedNames.firstIndex(of: anchor),
           let clickedIndex = displayedNames.firstIndex(of: template.name) {
            let range = Set(displayedNames[min(anchorIndex, clickedIndex)...max(anchorIndex, clickedIndex)])
            if isToggle {
                selectedTemplateNames.formUnion(range)
            } else {
                selectedTemplateNames = range
            }
            return
        }
        if isToggle {
            toggleSelection(of: template)
        } else {
            selectedTemplateNames = [template.name]
            selectionAnchorName = template.name
        }
        #else
        toggleSelection(of: template)
        #endif
    }

    /// Adds or removes one engine in the selection and moves the anchor that
    /// Shift-click ranges start from.
    private func toggleSelection(of template: Service) {
        if selectedTemplateNames.contains(template.name) {
            selectedTemplateNames.remove(template.name)
        } else {
            selectedTemplateNames.insert(template.name)
        }
        selectionAnchorName = template.name
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("AddEngineCancel")
            Spacer()
            Button(action: confirmSelection) {
                Text(confirmTitle)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(selectedTemplateNames.isEmpty)
            .accessibilityIdentifier("AddEngineConfirm")
        }
        .padding(16)
    }

    private var confirmTitle: String {
        let count = selectedTemplateNames.count
        guard count > 0 else { return "Add Engines" }
        return "Add \(count) Engine\(count == 1 ? "" : "s")"
    }

    private func confirmSelection() {
        let selection = templates
            .filter { selectedTemplateNames.contains($0.name) }
            .map { withoutConflictingShortcut($0) }
        guard !selection.isEmpty else { return }
        guard selection.contains(where: { isAlreadyAdded($0) }) else {
            onAddTemplates(selection)
            return
        }
        pendingSelection = selection
        showingDuplicateWarning = true
    }

    /// A new engine must not claim a launch shortcut another engine already
    /// owns: the hotkey manager registers each configuration once and
    /// activation resolves to the first engine holding it, so the shadowed
    /// copy would silently never fire while both Shortcuts rows claimed the
    /// key. Templates without a conflict keep their shortcut unchanged.
    private func withoutConflictingShortcut(_ template: Service) -> Service {
        #if os(macOS)
        guard let shortcut = template.activationShortcut,
              existingEngines.contains(where: { $0.activationShortcut == shortcut }) else {
            return template
        }
        var copy = template
        copy.activationShortcut = nil
        return copy
        #else
        return template
        #endif
    }

    private var duplicateWarningMessage: String {
        let count = pendingSelection.filter { isAlreadyAdded($0) }.count
        guard count > 1 else {
            return "One of your selected engines is already in your list — adding it will create a duplicate entry."
        }
        return "\(count) of your selected engines are already in your list — adding them will create duplicate entries."
    }
}

// MARK: - Platform chrome

#if os(macOS)
private let sheetBackground = Color(nsColor: .windowBackgroundColor)
private let tileBackground = Color(nsColor: .controlBackgroundColor)
private let tileBorder = Color(nsColor: .separatorColor)
#else
private let sheetBackground = Color(uiColor: .systemBackground)
private let tileBackground = Color(uiColor: .secondarySystemBackground)
private let tileBorder = Color(uiColor: .separator)
#endif

/// Fixed sheet size so the scrolling template grid and the footer both lay
/// out deterministically: fixed width on macOS, full width on iOS.
private struct SheetSizing: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .frame(width: 520, height: 500)
        #else
        content
            .frame(maxWidth: .infinity)
            .frame(height: 520)
        #endif
    }
}
