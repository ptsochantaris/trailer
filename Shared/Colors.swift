#if os(iOS)
    import UIKit

    typealias COLOR_CLASS = UIColor

#elseif os(macOS)
    import Cocoa

    typealias COLOR_CLASS = NSColor

#endif

extension COLOR_CLASS {
    static var appLabel: COLOR_CLASS {
        #if os(iOS)
            return .label
        #elseif os(macOS)
            return .labelColor
        #endif
    }

    static var appSecondaryLabel: COLOR_CLASS {
        #if os(iOS)
            return .secondaryLabel
        #elseif os(macOS)
            return .secondaryLabelColor
        #endif
    }

    static var appTertiaryLabel: COLOR_CLASS {
        #if os(iOS)
            return .tertiaryLabel
        #elseif os(macOS)
            return .tertiaryLabelColor
        #endif
    }

    var isDark: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: nil)
        let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return lum < 0.5
    }
}

extension StatusColour {
    /// The single place a status's meaning becomes an actual colour. Main-actor isolated,
    /// because the asset-catalog accessors are — which is precisely why `PRStatus` returns
    /// the enum rather than reaching for these itself.
    var uiColour: COLOR_CLASS {
        switch self {
        case .red: .appRed
        case .yellow: .appYellow
        case .green: .appGreen
        case .neutral: .appSecondaryLabel
        }
    }
}
