import Cocoa

final class StatusItemView: NSView {
    var icon: NSImage!
    var textAttributes = [NSAttributedString.Key: Any]()
    var countLabel = ""
    var title: String?

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    var grayOut = false {
        didSet {
            if grayOut != oldValue {
                needsDisplay = true
            }
        }
    }

    var highlighted = false {
        didSet {
            if highlighted != oldValue {
                needsDisplay = true
            }
        }
    }

    override var tag: Int {
        1947
    }

    static let prIcon: NSImage = {
        let img = NSImage(named: NSImage.Name("PullRequestIcon"))!
        var size = img.size
        let scale = 16.0 / size.height
        size.width *= scale
        size.height *= scale
        return img.resized(to: size, offset: NSPoint(x: 3, y: 3))
    }()

    static let issueIcon: NSImage = {
        let img = NSImage(named: NSImage.Name("IssueIcon"))!
        var size = img.size
        let scale = 16.0 / size.height
        size.width *= scale
        size.height *= scale
        return img.resized(to: size, offset: NSPoint(x: 3, y: 3))
    }()

    private func titleAttributes(foregorund: NSColor) -> [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        p.lineBreakMode = .byTruncatingMiddle
        return [
            .foregroundColor: foregorund,
            .font: NSFont.menuFont(ofSize: 6),
            .paragraphStyle: p
        ]
    }

    private let labelSpacing: CGFloat = 2

    func sizeToFit() {
        let H = NSStatusBar.system.thickness
        var itemWidth: CGFloat = 0
        if let title {
            itemWidth = icon.size.width - 6
            let titleWidth = title.size(withAttributes: titleAttributes(foregorund: .appLabel)).width
            itemWidth = max(itemWidth, titleWidth)
        } else {
            itemWidth = icon.size.width
        }

        if !countLabel.isEmpty {
            let countWidth = countLabel.size(withAttributes: textAttributes).width
            let extra = title == nil ? 0 : labelSpacing
            itemWidth = max(itemWidth, countWidth + icon.size.width + extra)
        }

        frame = CGRect(x: 0, y: 0, width: itemWidth, height: H)
    }

    private var isDark: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    override func draw(_: NSRect) {
        var countAttributes = textAttributes
        let foreground: NSColor

        if highlighted {
            foreground = .selectedMenuItemTextColor
        } else if isDark {
            foreground = .selectedMenuItemTextColor
            if countAttributes[.foregroundColor] as! NSColor == .labelColor {
                countAttributes[.foregroundColor] = foreground
            }
        } else {
            foreground = .controlTextColor
        }

        if grayOut {
            if isDark {
                countAttributes[.foregroundColor] = NSColor.secondaryLabelColor
            } else {
                countAttributes[.foregroundColor] = NSColor.disabledControlTextColor
            }
        }

        let tintedIcon = tintedImage(from: icon, tint: foreground)

        if let title {
            let r = CGRect(x: 0, y: bounds.height - 7, width: bounds.width, height: 7)
            title.draw(in: r, withAttributes: titleAttributes(foregorund: foreground))

            let iconWidth = tintedIcon.size.width - 6
            let countLabelWidth = countLabel.size(withAttributes: textAttributes).width
            let startX = ((bounds.width - (iconWidth + labelSpacing + countLabelWidth)) * 0.5).rounded(.up)

            tintedIcon.draw(in: CGRect(x: startX, y: 0, width: iconWidth, height: tintedIcon.size.height - 6))

            let countLabelRect = CGRect(x: startX + iconWidth + labelSpacing, y: -8, width: countLabelWidth, height: bounds.size.height)
            countLabel.draw(in: countLabelRect, withAttributes: countAttributes)

        } else {
            tintedIcon.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)

            let countLabelRect = if icon === StatusItemView.prIcon {
                CGRect(x: bounds.size.height - 2, y: -5, width: bounds.size.width, height: bounds.size.height)
            } else {
                CGRect(x: bounds.size.height - 0, y: -5, width: bounds.size.width, height: bounds.size.height)
            }
            countLabel.draw(in: countLabelRect, withAttributes: countAttributes)
        }
    }

    // With thanks to http://stackoverflow.com/questions/1413135/tinting-a-grayscale-nsimage-or-ciimage
    private func tintedImage(from image: NSImage, tint: NSColor) -> NSImage {
        let tinted = image.copy() as! NSImage
        tinted.lockFocus()
        tint.set()

        let imageRect = NSRect(origin: .zero, size: image.size)
        imageRect.fill(using: .sourceAtop)

        tinted.unlockFocus()
        return tinted
    }
}
