#if os(iOS)
    import UIKit

    typealias COLOR_CLASS = UIColor

#elseif os(macOS)
    import Cocoa

    typealias COLOR_CLASS = NSColor

#endif

extension COLOR_CLASS {
    static var appGreen: COLOR_CLASS {
        COLOR_CLASS(named: "appGreen")!
    }

    static var appYellow: COLOR_CLASS {
        COLOR_CLASS(named: "appYellow")!
    }

    static var appRed: COLOR_CLASS {
        COLOR_CLASS(named: "appRed")!
    }

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
