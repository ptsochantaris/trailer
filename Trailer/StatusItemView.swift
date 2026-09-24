import Cocoa

enum StatusItemView {
    enum State {
        case regular, grayed, highlighted, unread

        var foreground: NSColor {
            switch self {
            case .highlighted, .regular:
                .black
            case .grayed:
                .black.withAlphaComponent(0.6)
            case .unread:
                NSColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0)
            }
        }

        func titleAttributes(color: NSColor) -> [NSAttributedString.Key: Any] {
            let p = NSMutableParagraphStyle()
            p.alignment = .center
            p.lineBreakMode = .byTruncatingMiddle
            return [
                .foregroundColor: color,
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

    static func makeIcon(type: ListableItem.Type, state: State, countLabel: String, title: String?, appearance: NSAppearance) -> NSImage {
        // Everything except the red unread count is drawn black and returned as a template, so AppKit tints it to match the menu bar
        let baseColor: NSColor = state == .unread && appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .white : .black

        let stack = NSStackView()
        stack.spacing = 0
        stack.orientation = .vertical
        stack.alignment = .centerX

        let img: NSImage = type == PullRequest.self ? .pullRequestIcon : .issueIcon
        var size = img.size
        let scale = 16.0 / size.height
        size.width *= scale
        size.height *= scale

        let iconView = NSImageView()
        iconView.contentTintColor = baseColor
        iconView.imageAlignment = .alignCenter

        let icon = img.resized(to: size, offset: .zero)
        icon.isTemplate = true
        iconView.image = icon

        let bottomRow = NSStackView()
        bottomRow.orientation = .horizontal
        bottomRow.alignment = .centerY
        bottomRow.addArrangedSubview(iconView)

        if let title, !title.isEmpty {
            let titleText = PlainTextField(frame: .zero)
            titleText.attributedStringValue = NSAttributedString(string: title, attributes: state.titleAttributes(color: baseColor))
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
        sivImage.isTemplate = state != .unread

        return sivImage
    }
}
