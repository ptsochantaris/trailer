
Settings.checkMigration()
DataManager.checkMigration()
let api = API()

#if os(iOS)
	import UIKit
	UIApplicationMain(C_ARGC, C_ARGV, nil, NSStringFromClass(iOS_AppDelegate))
#else
	NSApplicationMain(C_ARGC, C_ARGV)
#endif
