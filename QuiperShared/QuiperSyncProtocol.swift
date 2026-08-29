import Foundation
#if os(iOS)
import UIKit
#endif

enum QuiperSyncProtocol {
    nonisolated static let serviceType = "_quiper-sync._tcp"
    nonisolated static let httpPath = "/quiper-config"
    nonisolated static let ackPath = "/quiper-ack"
    nonisolated static let serviceDomain: String? = nil

    nonisolated static var deviceDisplayName: String {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return Host.current().localizedName ?? "Mac"
        #endif
    }
}
