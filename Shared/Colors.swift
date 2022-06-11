#if os(iOS)
    import UIKit
    typealias COLOR_CLASS = UIColor

#elseif os(OSX)
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
        #elseif os(OSX)
            return .labelColor
        #endif
    }

    static var appSecondaryLabel: COLOR_CLASS {
        #if os(iOS)
            return .secondaryLabel
        #elseif os(OSX)
            return .secondaryLabelColor
        #endif
    }

    static var appTertiaryLabel: COLOR_CLASS {
        #if os(iOS)
            return .tertiaryLabel
        #elseif os(OSX)
            return .tertiaryLabelColor
        #endif
    }
}
