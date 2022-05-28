import UIKit

final class EmptyView: UIView {

	init(message: NSAttributedString, parentWidth: CGFloat) {

		let rect = message.boundingRect(with: CGSize(width: 280, height: CGFloat.greatestFiniteMagnitude),
			options: stringDrawingOptions,
			context: nil)
		let idealSize = rect.size

		super.init(frame: CGRect(x: 0, y: 0, width: parentWidth, height: idealSize.height+10.0))

		let text = UILabel(frame: CGRect(x: (parentWidth-idealSize.width)*0.5, y: 5.0, width: idealSize.width, height: idealSize.height+4.0))
		text.autoresizingMask = .flexibleWidth
		text.numberOfLines = 0
		text.attributedText = message
		addSubview(text)
	}

	required init(coder aDecoder: NSCoder) {
	    fatalError("init(coder:) has not been implemented")
	}
}
