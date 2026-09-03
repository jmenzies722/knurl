import Foundation
import SwiftUI

/// A dial the Hub can host that is not one of the five faces.
///
/// Tools deliberately sit outside `DialMode`: the five faces own the 1-5 keys,
/// the tint tables and the wire format the iPhone crown speaks, and PRODUCT.md
/// holds them at five. Adding a tool here costs one case and its crown config,
/// and touches none of that.
enum DeskTool: String, CaseIterable, Identifiable, Sendable {
    case hour
    case power

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hour: "Hour"
        case .power: "Power"
        }
    }

    var symbol: String {
        switch self {
        case .hour: "timer"
        case .power: "bolt.fill"
        }
    }

    @MainActor
    var tint: Color {
        switch self {
        case .hour: DialSwatch.bright
        case .power: DialSwatch.output
        }
    }
}
