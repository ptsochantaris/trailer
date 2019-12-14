//
//  Colors.swift
//  Trailer
//
//  Created by Paul Tsochantaris on 14/12/2019.
//

#if os(iOS)
import UIKit
typealias COLOR_CLASS = UIColor

#elseif os(OSX)
import Foundation
typealias COLOR_CLASS = NSColor

#endif

extension COLOR_CLASS {
    static var appGreen: COLOR_CLASS {
        if #available(OSX 10.13, iOS 13, *) {
            return COLOR_CLASS(named: "appGreen")!
        } else {
            return COLOR_CLASS(red: 0.3, green: 0.6, blue: 0.2, alpha: 1.0)
        }
    }

    static var appYellow: COLOR_CLASS {
        if #available(OSX 10.13, iOS 13, *) {
            return COLOR_CLASS(named: "appYellow")!
        } else {
            return COLOR_CLASS(red: 0.6, green: 0.6, blue: 0.0, alpha: 1.0)
        }
    }
    
    static var appRed: COLOR_CLASS {
        if #available(OSX 10.13, iOS 13, *) {
            return COLOR_CLASS(named: "appRed")!
        } else {
            return COLOR_CLASS(red: 0.7, green: 0.2, blue: 0.2, alpha: 1.0)
        }
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
