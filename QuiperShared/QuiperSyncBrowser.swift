import Combine
import Foundation
@preconcurrency import Network

struct DiscoveredSyncPeer: Identifiable, Equatable {
    let id: String
    let name: String
    let displayName: String
    let quipVersion: String?
    let endpoint: NWEndpoint
}

@MainActor
final class QuiperSyncBrowser: ObservableObject, @unchecked Sendable {
    @Published var peers: [DiscoveredSyncPeer] = []
    @Published var isBrowsing: Bool = false
    @Published var errorMessage: String?

    private var browser: NWBrowser?
    private let queue = DispatchQueue.main
    private var endpointMap: [String: DiscoveredSyncPeer] = [:]

    private final class WeakBox: @unchecked Sendable {
        weak var target: QuiperSyncBrowser?
        init(_ target: QuiperSyncBrowser) { self.target = target }
    }

    func start() {
        guard browser == nil else { return }
        errorMessage = nil
        peers = []
        endpointMap.removeAll()

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(
            type: QuiperSyncProtocol.serviceType,
            domain: QuiperSyncProtocol.serviceDomain
        )
        let browser = NWBrowser(for: descriptor, using: parameters)
        let box = WeakBox(self)
        browser.stateUpdateHandler = { state in
            Task { @MainActor in
                guard let self = box.target else { return }
                switch state {
                case .ready:
                    self.isBrowsing = true
                    self.errorMessage = nil
                case .failed(let error):
                    self.isBrowsing = false
                    self.errorMessage = error.localizedDescription
                case .cancelled:
                    self.isBrowsing = false
                default:
                    break
                }
            }
        }
        let resultsBox = WeakBox(self)
        browser.browseResultsChangedHandler = { results, _ in
            Task { @MainActor in
                guard let self = resultsBox.target else { return }
                self.update(results: results)
            }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        isBrowsing = false
    }

    func refresh() {
        stop()
        start()
    }

    private func update(results: Set<NWBrowser.Result>) {
        var newMap: [String: DiscoveredSyncPeer] = [:]
        for result in results {
            guard case .service(let name, let type, let domain, _) = result.endpoint else { continue }
            guard type == QuiperSyncProtocol.serviceType else { continue }
            let id = "\(name).\(type).\(domain)"
            let peer = DiscoveredSyncPeer(
                id: id,
                name: name,
                displayName: name,
                quipVersion: nil,
                endpoint: result.endpoint
            )
            newMap[id] = peer
        }
        endpointMap = newMap
        peers = Array(newMap.values).sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    deinit {
        browser?.cancel()
    }
}
