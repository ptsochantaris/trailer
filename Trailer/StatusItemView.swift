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
    private let stack = NSStackView()
    private let iconHeight: NSLayoutConstraint

    init(icon: NSImage, state: State, countLabel: String, title: String?) {
        self.icon = icon
        self.state = state
        self.countLabel = countLabel
        self.title = title

        iconHeight = iconView.heightAnchor.constraint(equalToConstant: 10)
        super.init(frame: .zero)

        icon.isTemplate = true
        iconView.image = icon
        iconHeight.isActive = true

        let bottomRow = NSStackView()
        bottomRow.spacing = 0
        bottomRow.orientation = .horizontal
        bottomRow.addArrangedSubview(iconView)
        bottomRow.addArrangedSubview(countText)

        stack.spacing = -1
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.addArrangedSubview(titleText)
        stack.addArrangedSubview(bottomRow)
        addSubview(stack)

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

    private let labelSpacing: CGFloat = 4

    private func updateUI() {
        iconView.contentTintColor = state.foreground

        if countLabel.isEmpty {
            countText.isHidden = true
        } else {
            countText.attributedStringValue = NSAttributedString(string: countLabel, attributes: state.countAttributes)
            countText.isHidden = false
        }

        if let title, !title.isEmpty {
            titleText.attributedStringValue = NSAttributedString(string: title, attributes: state.titleAttributes)
            titleText.isHidden = false
            iconHeight.constant = 16
        } else {
            titleText.isHidden = true
            iconHeight.constant = 20
        }

        let stackSize = stack.fittingSize
        let H = NSStatusBar.system.thickness
        let y = (H - stackSize.height) * 0.5
        let origin = CGPoint(x: 0, y: y.rounded(.down))
        stack.frame = CGRect(origin: origin, size: stackSize)
        frame = CGRect(origin: .zero, size: CGSize(width: stackSize.width, height: H))
    }
}
