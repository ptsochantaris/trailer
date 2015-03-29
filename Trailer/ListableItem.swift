
import CoreData
#if os(iOS)
	import UIKit
#endif

let itemDateFormatter = { () -> NSDateFormatter in
	let f = NSDateFormatter()
	f.doesRelativeDateFormatting = true
	f.dateStyle = NSDateFormatterStyle.MediumStyle
	f.timeStyle = NSDateFormatterStyle.ShortStyle
	return f
	}()

class ListableItem: DataItem {

	@NSManaged var assignedToMe: NSNumber?
	@NSManaged var body: String?
	@NSManaged var webUrl: String?
	@NSManaged var condition: NSNumber?
	@NSManaged var isNewAssignment: NSNumber?
	@NSManaged var comments: NSSet
	@NSManaged var labels: NSSet
	@NSManaged var repo: Repo
	@NSManaged var title: String?
	@NSManaged var totalComments: NSNumber?
	@NSManaged var unreadComments: NSNumber?
	@NSManaged var url: String?
	@NSManaged var userAvatarUrl: String?
	@NSManaged var userId: NSNumber?
	@NSManaged var userLogin: String?
	@NSManaged var sectionIndex: NSNumber?
	@NSManaged var latestReadCommentDate: NSDate?
	@NSManaged var state: String?
	@NSManaged var reopened: NSNumber?
	@NSManaged var number: NSNumber?

	override func prepareForDeletion() {
		api.refreshesSinceLastLabelsCheck[objectID] = nil
		api.refreshesSinceLastStatusCheck[objectID] = nil
		super.prepareForDeletion()
	}

	class func sortField() -> String? {
		switch (Settings.sortMethod) {
		case PRSortingMethod.CreationDate.rawValue: return "createdAt"
		case PRSortingMethod.RecentActivity.rawValue: return "updatedAt"
		case PRSortingMethod.Title.rawValue: return "title"
		default: return nil
		}
	}

	func sortedComments(comparison: NSComparisonResult) -> [PRComment] {
		return (comments.allObjects as! [PRComment]).sorted({ (c1, c2) -> Bool in
			let d1 = c1.createdAt ?? NSDate.distantPast() as! NSDate
			let d2 = c2.createdAt ?? NSDate.distantPast() as! NSDate
			return d1.compare(d2) == comparison
		})
	}

	func catchUpWithComments() {
		for c in comments.allObjects as! [PRComment] {
			if let creation = c.createdAt {
				if let latestRead = latestReadCommentDate {
					if latestRead.compare(creation)==NSComparisonResult.OrderedAscending {
						latestReadCommentDate = creation
					}
				} else {
					latestReadCommentDate = creation
				}
			}
		}
		postProcess()
	}

	func isMine() -> Bool {
		if let assigned = assignedToMe?.boolValue {
			if assigned && Settings.moveAssignedPrsToMySection {
				return true
			}
		}
		if let userId = userId {
			if let apiId = apiServer.userId {
				return userId == apiId
			}
		}
		return false
	}

	func refersToMe() -> Bool {
		if let apiName = apiServer.userName {
			if let b = body {
				let range = b.rangeOfString("@"+apiName, options: NSStringCompareOptions.CaseInsensitiveSearch | NSStringCompareOptions.DiacriticInsensitiveSearch)
				return range != nil
			}
		}
		return false
	}

	func commentedByMe() -> Bool {
		for c in comments.allObjects as! [PRComment] {
			if c.isMine() {
				return true
			}
		}
		return false
	}

	func refersToMyTeams() -> Bool {
		if let b = body {
			for t in apiServer.teams.allObjects as! [Team] {
				if let r = t.calculatedReferral {
					let range = b.rangeOfString(r, options: NSStringCompareOptions.CaseInsensitiveSearch | NSStringCompareOptions.DiacriticInsensitiveSearch)
					if range != nil { return true }
				}
			}
		}
		for c in comments.allObjects as! [PRComment] {
			if c.refersToMyTeams() {
				return true
			}
		}
		return false
	}

	func postProcess() {
		var section: PullRequestSection
		var currentCondition = condition?.integerValue ?? PullRequestCondition.Open.rawValue

		if currentCondition == PullRequestCondition.Merged.rawValue			{ section = PullRequestSection.Merged }
		else if currentCondition == PullRequestCondition.Closed.rawValue	{ section = PullRequestSection.Closed }
		else if isMine()													{ section = PullRequestSection.Mine }
		else if commentedByMe()												{ section = PullRequestSection.Participated }
		else if Settings.hideAllPrsSection									{ section = PullRequestSection.None }
		else																{ section = PullRequestSection.All }

		var needsManualCount = false
		var moveToParticipated = false
		let outsideMySections = (section == PullRequestSection.All || section == PullRequestSection.None)

		if outsideMySections && Settings.autoParticipateOnTeamMentions {
			if refersToMyTeams() {
				moveToParticipated = true
			} else {
				needsManualCount = true
			}
		}

		if !moveToParticipated && outsideMySections && Settings.autoParticipateInMentions {
			if refersToMe() {
				moveToParticipated = true
			} else {
				needsManualCount = true
			}
		}

		let f = NSFetchRequest(entityName: "PRComment")
		f.returnsObjectsAsFaults = false
		let latestDate = latestReadCommentDate

		if moveToParticipated {
			section = PullRequestSection.Participated
			f.predicate = predicateForOthersCommentsSinceDate(latestDate)
			unreadComments = managedObjectContext?.countForFetchRequest(f, error: nil)
		} else if needsManualCount {
			f.predicate = predicateForOthersCommentsSinceDate(nil)
			var unreadCommentCount: Int = 0
			for c in managedObjectContext?.executeFetchRequest(f, error: nil) as! [PRComment] {
				if c.refersToMe() {
					section = PullRequestSection.Participated
				}
				if let l = latestDate {
					if c.createdAt?.compare(l)==NSComparisonResult.OrderedDescending {
						unreadCommentCount++
					}
				} else {
					unreadCommentCount++;
				}
			}
			unreadComments = unreadCommentCount
		} else {
			f.predicate = predicateForOthersCommentsSinceDate(latestDate)
			unreadComments = managedObjectContext?.countForFetchRequest(f, error: nil)
		}

		sectionIndex = section.rawValue
		totalComments = comments.count

		if title==nil { title = "(No title)" }
	}

	func urlForOpening() -> String? {
		var unreadCount = unreadComments?.integerValue ?? 0

		if unreadCount > 0 && Settings.openPrAtFirstUnreadComment {
			let f = NSFetchRequest(entityName: "PRComment")
			f.returnsObjectsAsFaults = false
			f.fetchLimit = 1
			f.predicate = predicateForOthersCommentsSinceDate(latestReadCommentDate)
			f.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
			let ret = managedObjectContext?.executeFetchRequest(f, error: nil) as! [PRComment]
			if let firstComment = ret.first {
				if let url = firstComment.webUrl {
					return url
				}
			}
		}

		return webUrl
	}

	func accessibleTitle() -> String {
		var components = [String]()
		if let t = title { components.append(t) }
		if Settings.showLabels {
			var allLabels = labels.allObjects as! [PRLabel]
			allLabels.sort({ (l1: PRLabel, l2: PRLabel) -> Bool in
				return l1.name<l2.name
			})
			components.append("\(allLabels.count) labels:")
			for l in allLabels { if let n = l.name { components.append(n) } }
		}
		return ",".join(components)
	}

	func titleWithFont(font: FONT_CLASS, labelFont: FONT_CLASS, titleColor: COLOR_CLASS) -> NSMutableAttributedString {
		let p = NSMutableParagraphStyle()
		p.paragraphSpacing = 1.0

		let titleAttributes = [NSFontAttributeName: font, NSForegroundColorAttributeName: titleColor, NSParagraphStyleAttributeName: p]
		let _title = NSMutableAttributedString()
		if let t = title {
			_title.appendAttributedString(NSAttributedString(string: t, attributes: titleAttributes))
			if Settings.showLabels {
				var allLabels = labels.allObjects as! [PRLabel]
				if allLabels.count > 0 {

					_title.appendAttributedString(NSAttributedString(string: "\n", attributes: titleAttributes))

					let lp = NSMutableParagraphStyle()
					#if os(iOS)
						lp.lineHeightMultiple = 1.15
						let labelAttributes = [NSFontAttributeName: labelFont,
						NSBaselineOffsetAttributeName: 2.0,
						NSParagraphStyleAttributeName: lp]
						#elseif os(OSX)
						lp.minimumLineHeight = labelFont.pointSize+6.0
						let labelAttributes = [NSFontAttributeName: labelFont,
							NSBaselineOffsetAttributeName: 1.0,
							NSParagraphStyleAttributeName: lp]
					#endif

					allLabels.sort({ (l1: PRLabel, l2: PRLabel) -> Bool in
						return l1.name!.compare(l2.name!)==NSComparisonResult.OrderedAscending
					})

					var count = 0
					for l in allLabels {
						var a = labelAttributes
						let color = l.colorForDisplay()
						a[NSBackgroundColorAttributeName] = color
						a[NSForegroundColorAttributeName] = isDarkColor(color) ? COLOR_CLASS.whiteColor() : COLOR_CLASS.blackColor()
						let name = l.name!.stringByReplacingOccurrencesOfString(" ", withString: "\u{a0}")
						_title.appendAttributedString(NSAttributedString(string: "\u{a0}", attributes: a))
						_title.appendAttributedString(NSAttributedString(string: name, attributes: a))
						_title.appendAttributedString(NSAttributedString(string: "\u{a0}", attributes: a))
						if count<allLabels.count {
							_title.appendAttributedString(NSAttributedString(string: " ", attributes: labelAttributes))
						}
					}
				}
			}
		}
		return _title
	}

	func predicateForOthersCommentsSinceDate(optionalDate: NSDate?) -> NSPredicate {
		return NSPredicate() // should never reach here, always override
	}
}
