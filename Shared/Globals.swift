
///////////// Logging, with thanks to Transition.io: http://transition.io/logging-in-swift-without-overhead-in-production/

typealias LazyVarArgClosure = @autoclosure () -> CVarArgType?

func DLog(messageFormat:@autoclosure () -> String, args:LazyVarArgClosure...) {
	var shouldLog: Bool
	#if DEBUG
		shouldLog = true
	#else
		shouldLog = Settings.logActivityToConsole
	#endif
	if shouldLog {
		let realArgs:[CVarArgType] = args.map { (lazyArg:LazyVarArgClosure) in
			if let l = lazyArg() { return l } else { return "(nil)" }
		}

		func curriedStringWithFormat(valist:CVaListPointer) -> String {
			return NSString(format:messageFormat(), arguments:valist)
		}

		var s = withVaList(realArgs, curriedStringWithFormat)
		NSLog("%@", s)
	}
}

#if os(iOS)
	typealias COLOR_CLASS = UIColor
	typealias FONT_CLASS = UIFont
#elseif os(OSX)
	let STATUSITEM_PADDING: CGFloat = 1.0
	let TOP_HEADER_HEIGHT: CGFloat =  28.0
	let AVATAR_SIZE: CGFloat =  26.0
	let LEFTPADDING: CGFloat =  44.0
	let TITLE_HEIGHT: CGFloat =  42.0
	let BASE_BADGE_SIZE: CGFloat =  21.0
	let SMALL_BADGE_SIZE: CGFloat =  14.0
	let MENU_WIDTH: CGFloat =  500.0
	let AVATAR_PADDING: CGFloat =  8.0
	let REMOVE_BUTTON_WIDTH: CGFloat =  80.0

	typealias COLOR_CLASS = NSColor
	typealias FONT_CLASS = NSFont
#endif

func MAKECOLOR(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) -> COLOR_CLASS {
	return COLOR_CLASS(red: red, green: green, blue: blue, alpha: alpha)
}
