import Cocoa

final class StatusItemView: NSView {
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

    var icon: NSImage
    var countLabel: String
    var title: String?
    var state: State {
        didSet {
            if state != oldValue {
                updateUI()
            }
        }
    }

    private let iconView = NSImageView()
    private let titleText = PlainTextField(frame: .zero)
    private let countText = PlainTextField(frame: .zero)

    init(icon: NSImage, state: State, countLabel: String, title: String?) {
        self.icon = icon
        self.state = state
        self.countLabel = countLabel
        self.title = title
        super.init(frame: .zero)

        addSubview(titleText)
        addSubview(countText)
        addSubview(iconView)

        icon.isTemplate = true
        iconView.image = icon

        updateUI()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }

    override var tag: Int {
        1947
    }

    static let prIcon: NSImage = {
        let img = NSImage.pullRequestIcon
        var size = img.size
        let scale = 16.0 / size.height
        size.width *= scale
        size.height *= scale
        return img.resized(to: size, offset: NSPoint(x: 3, y: 3))
    }()

    static let issueIcon: NSImage = {
        let img = NSImage.issueIcon
        var size = img.size
        let scale = 16.0 / size.height
        size.width *= scale
        size.height *= scale
        return img.resized(to: size, offset: NSPoint(x: 3, y: 3))
    }()

    private let labelSpacing: CGFloat = 2

    private func updateUI() {
        iconView.contentTintColor = state.foreground

        let H = NSStatusBar.system.thickness
        let iconWidth = icon.size.width - 2
        let titleAttributes = state.titleAttributes
        let countAttributes = state.countAttributes

        let countWidth: CGFloat
        if countLabel.isEmpty {
            countText.isHidden = true
            countWidth = 0

        } else {
            countText.attributedStringValue = NSAttributedString(string: countLabel, attributes: countAttributes)
            countText.sizeToFit()
            countText.isHidden = false
            countWidth = countText.frame.width
        }

        let iconAndCountWidth = countWidth + iconWidth + (countWidth == 0 ? 0 : labelSpacing)
        let itemWidth: CGFloat
        let isPr = icon === StatusItemView.prIcon

        if let title {
            titleText.attributedStringValue = NSAttributedString(string: title, attributes: titleAttributes)
            titleText.sizeToFit()
            let titleWidth = titleText.frame.width
            itemWidth = max(iconAndCountWidth, titleWidth)
            titleText.frame = CGRect(x: 0, y: H - 7, width: itemWidth, height: 7)
            titleText.isHidden = false

            let startX = ((itemWidth - iconAndCountWidth) * 0.5).rounded(.up)
            iconView.frame = CGRect(x: startX, y: 0, width: iconWidth, height: icon.size.height - 6)

            let iconWidth = icon.size.width - 6
            let extra: CGFloat = isPr ? 1 : 0
            countText.frame = CGRect(x: startX + iconWidth + labelSpacing + extra, y: -4, width: countWidth, height: H)

            frame = CGRect(x: 0, y: 0, width: itemWidth - 1, height: H)

        } else {
            itemWidth = iconAndCountWidth
            iconView.frame = CGRect(x: 0, y: 0, width: iconWidth, height: H)
            titleText.isHidden = true
            let deduction: CGFloat = isPr ? 5 : 2
            countText.frame = CGRect(x: H - deduction, y: -1, width: countWidth, height: H)

            frame = CGRect(x: 0, y: 0, width: itemWidth - deduction, height: H)
        }
    }
}
