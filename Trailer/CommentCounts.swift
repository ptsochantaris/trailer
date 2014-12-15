

class CommentCounts: NSView {

	init(frame: NSRect, unreadCount: Int, totalCount: Int) {

		super.init(frame: frame)

		if totalCount > 0 {

			let pCenter = NSMutableParagraphStyle()
			pCenter.alignment = NSTextAlignment.CenterTextAlignment

			let redFill = MAKECOLOR(1.0, 0.4, 0.4, 1.0)

			let numberFormatter = NSNumberFormatter()
			numberFormatter.numberStyle = NSNumberFormatterStyle.DecimalStyle;

			self.canDrawSubviewsIntoLayer = true

			let statusView = app.statusItem.view as StatusItemView
			let darkMode = statusView.darkMode

			let countString = NSAttributedString(string: numberFormatter.stringFromNumber(totalCount)!, attributes: [
				NSFontAttributeName: NSFont.menuFontOfSize(11),
				NSForegroundColorAttributeName: darkMode ? COLOR_CLASS.controlLightHighlightColor() : COLOR_CLASS.controlTextColor(),
				NSParagraphStyleAttributeName: pCenter])

			var width = max(CGFloat(BASE_BADGE_SIZE), CGFloat(countString.size.width)+10)
			var height = CGFloat(BASE_BADGE_SIZE)
			var bottom = (self.bounds.size.height-height)*0.5
			var left = (self.bounds.size.width-width)*0.5

			let countBackground = NSView(frame: NSIntegralRect(NSMakeRect(left, bottom, width, height)))
			countBackground.wantsLayer = true
			countBackground.layer!.cornerRadius = 4.0
			let color = MAKECOLOR(0.94, 0.94, 0.94, 1.0).CGColor;
			if MenuWindow.usingVibrancy() && statusView.darkMode {
				countBackground.layer!.backgroundColor = COLOR_CLASS.clearColor().CGColor
				countBackground.layer!.borderColor = color
				countBackground.layer!.borderWidth = 0.5
			} else {
				countBackground.layer!.backgroundColor = color
			}
			self.addSubview(countBackground)

			let countView = CenterTextField(frame: countBackground.bounds)
			countView.attributedStringValue = countString
			countBackground.addSubview(countView)

			if unreadCount > 0 {

				let alertString = NSAttributedString(string: numberFormatter.stringFromNumber(unreadCount)!, attributes: [
					NSFontAttributeName: NSFont.menuFontOfSize(8),
					NSForegroundColorAttributeName: NSColor.whiteColor(),
					NSParagraphStyleAttributeName: pCenter])

				bottom += height
				width = max(CGFloat(SMALL_BADGE_SIZE), alertString.size.width+8)
				height = CGFloat(SMALL_BADGE_SIZE)
				bottom -= height * 0.5 + 1
				left -= width * 0.5

				let alertBackground = NSView(frame: NSIntegralRect(NSMakeRect(left, bottom, width, height)))
				alertBackground.wantsLayer = true
				alertBackground.layer!.backgroundColor = redFill.CGColor
				alertBackground.layer!.cornerRadius = CGFloat(floor(SMALL_BADGE_SIZE*0.5))
				self.addSubview(alertBackground, positioned: NSWindowOrderingMode.Below, relativeTo: countBackground)

				let alertView = CenterTextField(frame: NSOffsetRect(alertBackground.bounds, 0, 1))
				alertView.attributedStringValue = alertString
				alertBackground.addSubview(alertView)
			}
		}
	}

	required init?(coder: NSCoder) {
	    fatalError("init(coder:) has not been implemented")
	}

}
