import Cocoa

enum StatusItemView {
    enum State {
        case regular, grayed, highlighted, unread

        var foreground: NSColor {
            switch self {
            case .regular:
                .controlTextColor
            case .grayed:
                .controlTextColor.withAlphaComponent(0.6)
            case .highlighted:
                .selectedMenuItemTextColor
            case .unread:
                NSColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0)
            }
        }

        var titleAttributes: [NSAttributedString.Key: Any] {
            let p = NSMutableParagraphStyle()
            p.alignment = .center
            p.lineBreakMode = .byTruncatingMiddle
            return [
                .foregroundColor: NSColor.controlTextColor,
                .font: NSFont.menuFont(ofSize: 6),
                .paragraphStyle: p
            ]
        }

        var countAttributes: [NSAttributedString.Key: Any] {
            switch self {
            case .regular:
                [.font: NSFont.menuBarFont(ofSize: 10), .foregroundColor: foreground]
            case .grayed:
                [.font: NSFont.menuBarFont(ofSize: 10), .foregroundColor: foreground]
            case .highlighted:
                [.font: NSFont.boldSystemFont(ofSize: 10), .foregroundColor: foreground]
            case .unread:
                [.font: NSFont.boldSystemFont(ofSize: 10), .foregroundColor: foreground]
            }
        }
    }

    static func makeIcon(icon: NSImage, state: State, countLabel: String, title: String?) -> NSImage {
        let stack = NSStackView()
        stack.spacing = 0
        stack.orientation = .vertical
        stack.alignment = .centerX

        let iconView = NSImageView()
        iconView.contentTintColor = state.foreground
        iconView.imageAlignment = .alignCenter
        iconView.image = icon

        let bottomRow = NSStackView()
        bottomRow.orientation = .horizontal
        bottomRow.alignment = .centerY
        bottomRow.addArrangedSubview(iconView)

        if let title, !title.isEmpty {
            let titleText = PlainTextField(frame: .zero)
            titleText.attributedStringValue = NSAttributedString(string: title, attributes: state.titleAttributes)
            titleText.widthAnchor.constraint(equalToConstant: titleText.fittingSize.width).isActive = true
            stack.addArrangedSubview(titleText)

            iconView.heightAnchor.constraint(equalToConstant: 11).isActive = true
            bottomRow.spacing = 0
        } else {
            iconView.heightAnchor.constraint(equalToConstant: 15).isActive = true
            bottomRow.spacing = 1
        }

        if !countLabel.isEmpty {
            let countText = PlainTextField(frame: .zero)
            countText.attributedStringValue = NSAttributedString(string: countLabel, attributes: state.countAttributes)
            countText.widthAnchor.constraint(equalToConstant: countText.fittingSize.width).isActive = true
            bottomRow.addArrangedSubview(countText)
        }

        stack.addArrangedSubview(bottomRow)

        let stackSize = stack.fittingSize
        let stackRect = NSRect(origin: .zero, size: stackSize)

        let sivImage = NSImage(size: stackSize)
        if let bir = stack.bitmapImageRepForCachingDisplay(in: stackRect) {
            bir.size = stackSize
            stack.cacheDisplay(in: stackRect, to: bir)
            sivImage.addRepresentation(bir)
        }
        sivImage.isTemplate = true
        return sivImage
    }

    static let prIcon: NSImage = {
        let img = NSImage.pullRequestIcon
        var size = img.size
        let scale = 16.0 / size.height
        size.width *= scale
        size.height *= scale
        return img.resized(to: size, offset: .zero)
    }()

    static let issueIcon: NSImage = {
        let img = NSImage.issueIcon
        var size = img.size
        let scale = 16.0 / size.height
        size.width *= scale
        size.height *= scale
        return img.resized(to: size, offset: .zero)
    }()
}
