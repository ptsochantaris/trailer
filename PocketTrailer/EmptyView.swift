import UIKit

final class EmptyView: UIView {
    let textLabel: UILabel

    init(message: NSAttributedString) {
        textLabel = UILabel(frame: .zero)
        textLabel.numberOfLines = 0
        textLabel.attributedText = message

        super.init(frame: .zero)

        addSubview(textLabel)
    }

    override func layoutSubviews() {
        textLabel.sizeToFit()

        let x = readableContentGuide.layoutFrame.midX - textLabel.frame.width * 0.5
        textLabel.frame.origin = CGPoint(x: x, y: 5)
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
