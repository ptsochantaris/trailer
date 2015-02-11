
class CommentCounts: NSView {

    let countBackground: NSView?
    let countView: CenterTextField?
    let countColor: NSColor?

    init(frame: NSRect, unreadCount: Int, totalCount: Int, goneDark: Bool) {

		super.init(frame: frame)

		if totalCount > 0 {
			let pCenter = NSMutableParagraphStyle()
			pCenter.alignment = NSTextAlignment.CenterTextAlignment

			let redFill = MAKECOLOR(1.0, 0.4, 0.4, 1.0)

			let numberFormatter = NSNumberFormatter()
			numberFormatter.numberStyle = NSNumberFormatterStyle.DecimalStyle

			canDrawSubviewsIntoLayer = true

            countColor = goneDark ? NSColor.controlLightHighlightColor() : NSColor.controlTextColor()

			let countString = NSAttributedString(string: numberFormatter.stringFromNumber(totalCount)!, attributes: [
				NSFontAttributeName: NSFont.menuFontOfSize(11),
				NSForegroundColorAttributeName: countColor!,
				NSParagraphStyleAttributeName: pCenter])

			var width = max(BASE_BADGE_SIZE, countString.size.width+10)
			var height = BASE_BADGE_SIZE
			var bottom = (bounds.size.height-height)*0.5
			var left = (bounds.size.width-width)*0.5

			let c = NSView(frame: NSIntegralRect(NSMakeRect(left, bottom, width, height)))
			c.wantsLayer = true
			c.layer!.cornerRadius = 4.0
			addSubview(c)

            countView = CenterTextField(frame: c.bounds)
			countView!.attributedStringValue = countString
			c.addSubview(countView!)

            countBackground = c
            highlight(false)

			if unreadCount > 0 {

				let alertString = NSAttributedString(string: numberFormatter.stringFromNumber(unreadCount)!, attributes: [
					NSFontAttributeName: NSFont.menuFontOfSize(8),
					NSForegroundColorAttributeName: NSColor.whiteColor(),
					NSParagraphStyleAttributeName: pCenter])

				bottom += height
				width = max(SMALL_BADGE_SIZE, alertString.size.width+8)
				height = SMALL_BADGE_SIZE
				bottom -= height * 0.5 + 1
				left -= width * 0.5

				let alertBackground = CenterTextField(frame: NSIntegralRect(NSMakeRect(left, bottom, width, height)))
				alertBackground.wantsLayer = true
				alertBackground.layer!.backgroundColor = redFill.CGColor
				alertBackground.layer!.cornerRadius = floor(SMALL_BADGE_SIZE*0.5)
				alertBackground.attributedStringValue = alertString
				addSubview(alertBackground, positioned: NSWindowOrderingMode.Below, relativeTo: countBackground)
			}
		}
	}

    func highlight(on: Bool) -> Void {
        if let c = countBackground {
            var color: NSColor
            if MenuWindow.usingVibrancy() && (app.statusItem.view as StatusItemView).darkMode {
                color = on ? NSColor.blackColor() : MAKECOLOR(0.94, 0.94, 0.94, 1.0)
                c.layer!.backgroundColor = NSColor.clearColor().CGColor
                c.layer!.borderColor = color.CGColor
                c.layer!.borderWidth = 0.5
            } else {
                color = self.countColor!
                c.layer!.backgroundColor = MAKECOLOR(0.94, 0.94, 0.94, 1.0).CGColor
            }
            if let a = countView?.attributedStringValue.mutableCopy() as? NSMutableAttributedString {
                a.addAttribute(NSForegroundColorAttributeName, value: color, range: NSMakeRange(0, a.length))
                countView?.attributedStringValue = a
            }
        }
    }

	func allowsVibrancy() -> Bool {
		return true
	}

	required init?(coder: NSCoder) {
	    fatalError("init(coder:) has not been implemented")
	}

}
