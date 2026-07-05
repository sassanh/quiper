import AppKit
import WebKit

@MainActor
final class TabHistoryHUDView: NSView {
    
    private weak var wc: MainWindowController?
    private let visualEffectView: NSVisualEffectView
    private let rowsStackView = NSStackView()
    
    private(set) var currentItemsCount = 0
    private(set) var currentMaxItemsPerRow = 3
    
    init(frame frameRect: NSRect, windowController: MainWindowController) {
        self.wc = windowController
        
        visualEffectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: frameRect.size))
        
        super.init(frame: frameRect)
        
        self.appearance = NSAppearance(named: .vibrantDark)
        self.autoresizingMask = [.width, .height]
        
        // Base view shadow styling
        self.wantsLayer = true
        self.layer?.cornerRadius = 16
        self.layer?.shadowColor = NSColor.black.cgColor
        self.layer?.shadowOpacity = 0.5
        self.layer?.shadowOffset = CGSize(width: 0, height: -6)
        self.layer?.shadowRadius = 16
        self.layer?.backgroundColor = NSColor.clear.cgColor
        
        // Visual Effect backdrop with rounded mask and border
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 16
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        visualEffectView.layer?.borderWidth = 1
        visualEffectView.material = .hudWindow
        visualEffectView.state = .active
        visualEffectView.blendingMode = .withinWindow
        addSubview(visualEffectView)
        
        // Premium dark backing layer overlay to increase contrast
        let darkBacking = NSView(frame: bounds)
        darkBacking.autoresizingMask = [.width, .height]
        darkBacking.wantsLayer = true
        darkBacking.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
        visualEffectView.addSubview(darkBacking)
        
        setupStackView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupStackView() {
        rowsStackView.orientation = .vertical
        rowsStackView.spacing = 12
        rowsStackView.alignment = .leading
        
        visualEffectView.addSubview(rowsStackView)
        rowsStackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rowsStackView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 16),
            rowsStackView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -16),
            rowsStackView.topAnchor.constraint(equalTo: visualEffectView.topAnchor, constant: 16),
            rowsStackView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor, constant: -16)
        ])
    }
    
    func updateSelection() {
        guard let wc = wc else { return }
        
        // Rebuild rowsStackView to display all items in the ring
        rowsStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        var items: [TabIdentifier] = []
        if let start = wc.cyclingStartTab {
            items.append(start)
        }
        for tab in wc.tabHistory {
            if !items.contains(tab) {
                items.append(tab)
            }
        }
        
        guard !items.isEmpty else { return }
        
        // Dynamic row items selection logic to maximize items in last row (choosing between 3, 4, and 5)
        let n = items.count
        self.currentItemsCount = n
        
        let lastRow3 = n % 3 == 0 ? 3 : n % 3
        let lastRow4 = n % 4 == 0 ? 4 : n % 4
        let lastRow5 = n % 5 == 0 ? 5 : n % 5
        
        let maxItemsPerRow: Int
        if lastRow5 >= lastRow4 && lastRow5 >= lastRow3 && n >= 5 {
            maxItemsPerRow = 5
        } else if lastRow4 >= lastRow3 && lastRow4 >= lastRow5 && n >= 4 {
            maxItemsPerRow = 4
        } else {
            maxItemsPerRow = 3
        }
        self.currentMaxItemsPerRow = maxItemsPerRow
        
        let itemWidth: CGFloat = 148
        
        let activeTab: TabIdentifier?
        if wc.isCyclingHistory {
            activeTab = wc.highlightedTab
        } else if let svc = wc.currentService() {
            let activeIndex = wc.activeIndicesByURL[svc.url] ?? 0
            activeTab = TabIdentifier(serviceURL: svc.url, sessionIndex: activeIndex)
        } else {
            activeTab = nil
        }
        
        // Split items into chunks of maxItemsPerRow
        var chunks: [[TabIdentifier]] = []
        var currentChunk: [TabIdentifier] = []
        for item in items {
            currentChunk.append(item)
            if currentChunk.count == maxItemsPerRow {
                chunks.append(currentChunk)
                currentChunk = []
            }
        }
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }
        
        for chunk in chunks {
            let rowStack = NSStackView()
            rowStack.orientation = .horizontal
            rowStack.spacing = 12
            rowStack.alignment = .centerY
            rowStack.distribution = .fill
            
            for tab in chunk {
                let isActive = (tab == activeTab)
                let card = createTabCard(for: tab, isActive: isActive, width: itemWidth)
                rowStack.addArrangedSubview(card)
            }
            
            rowsStackView.addArrangedSubview(rowStack)
        }
        
        self.needsLayout = true
    }
    
    private func createTabCard(for tab: TabIdentifier, isActive: Bool, width: CGFloat) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.masksToBounds = true
        
        card.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            card.widthAnchor.constraint(equalToConstant: width),
            card.heightAnchor.constraint(equalToConstant: 130)
        ])
        
        // Highlight active border
        if isActive {
            card.layer?.borderColor = NSColor.black.cgColor
            card.layer?.borderWidth = 3.0
        } else {
            card.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
            card.layer?.borderWidth = 1.0
        }
        
        // Find corresponding service
        let service = wc?.services.first { $0.url == tab.serviceURL }
        let tabNum = tab.sessionIndex == 9 ? 10 : tab.sessionIndex + 1
        
        let pageTitle: String
        if let svc = service, let wv = wc?.webViewManager.getWebView(for: svc, sessionIndex: tab.sessionIndex), let title = wv.title, !title.isEmpty {
            pageTitle = title
        } else {
            pageTitle = "Empty Session"
        }
        
        if let previewImage = wc?.tabPreviews[tab],
           let cgImage = previewImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            
            // Preview Image view at the top 90pt
            let previewView = NSView()
            previewView.wantsLayer = true
            previewView.layer?.contentsGravity = .resizeAspectFill
            previewView.layer?.contents = cgImage
            previewView.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(previewView)
            
            NSLayoutConstraint.activate([
                previewView.topAnchor.constraint(equalTo: card.topAnchor),
                previewView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
                previewView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
                previewView.heightAnchor.constraint(equalToConstant: 90)
            ])
            
        } else {
            // Leave background transparent if preview is not available
            card.layer?.backgroundColor = NSColor.clear.cgColor
        }
        
        // Bottom Overlay (identical layout for both preview/gradient cases)
        let overlayView = NSView()
        overlayView.wantsLayer = true
        overlayView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(overlayView)
        
        NSLayoutConstraint.activate([
            overlayView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            overlayView.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        // Digit on the Left
        let digitContainer = NSView()
        digitContainer.translatesAutoresizingMaskIntoConstraints = false
        overlayView.addSubview(digitContainer)
        
        let digitField = NSTextField(labelWithString: "\(tabNum)")
        digitField.font = .systemFont(ofSize: 22, weight: .bold)
        digitField.textColor = isActive ? NSColor.controlAccentColor : NSColor.white.withAlphaComponent(0.65)
        digitField.alignment = .center
        digitField.translatesAutoresizingMaskIntoConstraints = false
        digitContainer.addSubview(digitField)
        
        NSLayoutConstraint.activate([
            digitContainer.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor),
            digitContainer.topAnchor.constraint(equalTo: overlayView.topAnchor),
            digitContainer.bottomAnchor.constraint(equalTo: overlayView.bottomAnchor),
            digitContainer.widthAnchor.constraint(equalToConstant: 28),
            
            digitField.centerXAnchor.constraint(equalTo: digitContainer.centerXAnchor),
            digitField.centerYAnchor.constraint(equalTo: digitContainer.centerYAnchor)
        ])
        
        // Title on the Right (2-line wrapping label)
        let titleField = NSTextField()
        titleField.isEditable = false
        titleField.isSelectable = false
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.font = .systemFont(ofSize: 10, weight: .semibold)
        titleField.textColor = isActive ? .white : NSColor.white.withAlphaComponent(0.7)
        titleField.alignment = .left
        titleField.cell?.wraps = true
        titleField.cell?.usesSingleLineMode = false
        titleField.cell?.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 2
        titleField.stringValue = pageTitle
        titleField.translatesAutoresizingMaskIntoConstraints = false
        overlayView.addSubview(titleField)
        
        NSLayoutConstraint.activate([
            titleField.leadingAnchor.constraint(equalTo: digitContainer.trailingAnchor, constant: 4),
            titleField.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor, constant: -6),
            titleField.centerYAnchor.constraint(equalTo: overlayView.centerYAnchor),
            titleField.heightAnchor.constraint(equalToConstant: 28)
        ])
        
        return card
    }
}
