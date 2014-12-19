
class EmptyView: UIView {

	init(message: NSAttributedString) {

		let rect = message.boundingRectWithSize(CGSizeMake(280, CGFloat.max),
			options: stringDrawingOptions,
			context: nil)
		let idealSize = rect.size

		super.init(frame: CGRectMake(0, 0, 320, idealSize.height+10.0))

		let text = UILabel(frame: CGRectMake((320-idealSize.width)*0.5, 5.0, idealSize.width, idealSize.height+4.0))
		text.numberOfLines = 0
		text.attributedText = message
		self.addSubview(text)
	}

	required init(coder aDecoder: NSCoder) {
	    fatalError("init(coder:) has not been implemented")
	}
}
