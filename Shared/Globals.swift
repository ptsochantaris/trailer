
///////////// Logging, with thanks to Transition.io: http://transition.io/logging-in-swift-without-overhead-in-production/

typealias LazyVarArgClosure = @autoclosure () -> CVarArgType?

func DLog(messageFormat:@autoclosure () -> String, args:LazyVarArgClosure...) {
	var shouldLog: Bool
	#if DEBUG
		shouldLog = true
	#else
		shouldLog = settings.logActivityToConsole
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
	typealias COLOR_CLASS = NSColor
	typealias FONT_CLASS = NSFont
#endif

func MAKECOLOR(red: CGFloat, _ green: CGFloat, _ blue: CGFloat,  _ alpha: CGFloat) -> COLOR_CLASS {
	return COLOR_CLASS(red: red, green: green, blue: blue, alpha: alpha)
}

let kPullRequestSectionNames = ["", "Mine", "Participated", "Recently Merged", "Recently Closed", "All Pull Requests"]
