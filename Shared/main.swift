
currentAppVersion = NSBundle.mainBundle().infoDictionary!["CFBundleShortVersionString"] as String
DataManager.checkMigration()

#if os(iOS)
	UIApplicationMain(C_ARGC, C_ARGV, nil, NSStringFromClass(iOS_AppDelegate));
#else
	NSApplicationMain(C_ARGC, C_ARGV)
#endif
