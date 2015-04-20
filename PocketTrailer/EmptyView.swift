
import UIKit

final class EmptyView: UIView {

	init(message: NSAttributedString, parentWidth: CGFloat) {

		let rect = message.boundingRectWithSize(CGSizeMake(280, CGFloat.max),
			options: stringDrawingOptions,
			context: nil)
		let idealSize = rect.size

		super.init(frame: CGRectMake(0, 0, parentWidth, idealSize.height+10.0))

		let text = UILabel(frame: CGRectMake((parentWidth-idealSize.width)*0.5, 5.0, idealSize.width, idealSize.height+4.0))
		text.autoresizingMask = UIViewAutoresizing.FlexibleWidth
		text.numberOfLines = 0
		text.attributedText = message
		addSubview(text)
	}

	required init(coder aDecoder: NSCoder) {
	    fatalError("init(coder:) has not been implemented")
	}
}
