// With many thanks to: http://stackoverflow.com/questions/26475008/swift-getting-a-mac-app-to-launch-on-startup

final class StartupLaunch: NSObject {

	class func isAppLoginItem() -> Bool {
		return (itemReferencesInLoginItems().existingReference != nil)
	}

	private class func itemReferencesInLoginItems() -> (existingReference: LSSharedFileListItemRef?, lastReference: LSSharedFileListItemRef?) {

		if let loginItemsRef = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeRetainedValue(), nil).takeRetainedValue() as LSSharedFileListRef? {
			let loginItems = LSSharedFileListCopySnapshot(loginItemsRef, nil).takeRetainedValue() as NSArray as! [LSSharedFileListItemRef]
			if loginItems.count > 0 {

				let appUrl = NSURL.fileURLWithPath(NSBundle.mainBundle().bundlePath)
				let itemUrl = UnsafeMutablePointer<Unmanaged<CFURL>?>.alloc(1)
				defer { itemUrl.destroy() }

				for i in loginItems {
					if LSSharedFileListItemResolve(i, 0, itemUrl, nil) == noErr, let urlRef: NSURL = itemUrl.memory?.takeRetainedValue() where urlRef.isEqual(appUrl) {
						return (i, loginItems.last)
					}
				}
				return (nil, loginItems.last)
			} else {
				return(nil, kLSSharedFileListItemBeforeFirst.takeRetainedValue())
			}
		}
		return (nil, nil)
	}

	class func setLaunchOnLogin(launch: Bool) {

		let itemReferences = itemReferencesInLoginItems()
		let isSet = (itemReferences.existingReference != nil)
		if let loginItemsRef = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeRetainedValue(), nil).takeRetainedValue() as LSSharedFileListRef? {
			if launch && !isSet {
				if let appUrl : CFURLRef = NSURL.fileURLWithPath(NSBundle.mainBundle().bundlePath) {
					LSSharedFileListInsertItemURL(loginItemsRef, itemReferences.lastReference, nil, nil, appUrl, nil, nil)
					DLog("Trailer was added to login items")
				}
			} else if !launch && isSet {
				if let itemRef = itemReferences.existingReference {
					LSSharedFileListItemRemove(loginItemsRef,itemRef)
					DLog("Trailer was removed from login items")
				}
			}
		}
	}
	
}
