
import CoreData
#if os(iOS)
	import UIKit
#endif

@objc (Issue)
class Issue: DataItem {

	@NSManaged var body: String?
	@NSManaged var webUrl: String?
	@NSManaged var title: String?
	@NSManaged var sectionIndex: NSNumber?
	@NSManaged var totalComments: NSNumber?
	@NSManaged var unreadComments: NSNumber?
	@NSManaged var condition: NSNumber?
	@NSManaged var userAvatarUrl: String?
	@NSManaged var userId: NSNumber?
	@NSManaged var userLogin: String?
	@NSManaged var latestReadCommentDate: NSDate?
	@NSManaged var url: String?
	@NSManaged var assignedToMe: NSNumber?
	@NSManaged var number: NSNumber?
	@NSManaged var commentsLink: String?
	@NSManaged var state: String?
	@NSManaged var reopened: NSNumber?
	@NSManaged var isNewAssignment: NSNumber?

	@NSManaged var labels: NSSet
	@NSManaged var comments: NSSet
	@NSManaged var repo: Repo

	class func issueWithInfo(info: NSDictionary, fromServer: ApiServer, inRepo: Repo) -> Issue {
		let i = DataItem.itemWithInfo(info, type: "Issue", fromServer: fromServer) as! Issue
		if i.postSyncAction?.integerValue != PostSyncAction.DoNothing.rawValue {
			i.url = info.ofk("url") as? String
			i.webUrl = info.ofk("html_url") as? String
			i.number = info.ofk("number") as? NSNumber
			i.state = info.ofk("state") as? String
			i.title = info.ofk("title") as? String
			i.body = info.ofk("body") as? String
			i.repo = inRepo

			if let userInfo = info.ofk("user") as? NSDictionary {
				i.userId = userInfo.ofk("id") as? NSNumber
				i.userLogin = userInfo.ofk("login") as? String
				i.userAvatarUrl = userInfo.ofk("avatar_url") as? String
			}

			if let N = i.number {
				if let R = inRepo.fullName {
					i.commentsLink = "/repos/\(R)/issues/\(N)/comments"
				}
			}

			for existingLabel in i.labels.allObjects as! [PRLabel] {
				existingLabel.postSyncAction = PostSyncAction.Delete.rawValue
			}

			if let labelsList = info.ofk("labels") as? [NSDictionary] {
				for labelInfo in labelsList {
					PRLabel.labelWithInfo(labelInfo, withParent: i)
				}
			}

			if let assignee = info.ofk("assignee") as? NSDictionary {
				let assigneeName = assignee.ofk("login") as? String ?? "NoAssignedUserName"
				let assigned = (assigneeName == (fromServer.userName ?? "NoApiUser"))
				i.isNewAssignment = (assigned && !(i.assignedToMe?.boolValue ?? false))
				i.assignedToMe = assigned
			} else {
				i.assignedToMe = false
				i.isNewAssignment = false
			}
		}
		i.reopened = ((i.condition?.integerValue ?? 0) == PullRequestCondition.Closed.rawValue)
		i.condition = PullRequestCondition.Open.rawValue
		return i
	}

	class func requestForIssuesWithFilter(filter: String?, sectionIndex: Int) -> NSFetchRequest {

		var andPredicates = [NSPredicate]()
		if sectionIndex<0 {
			andPredicates.append(NSPredicate(format: "sectionIndex > 0"))
		} else {
			andPredicates.append(NSPredicate(format: "sectionIndex == %d", sectionIndex))
		}

		if let fi = filter {
			if !fi.isEmpty {

				var orPredicates = [NSPredicate]()
				orPredicates.append(NSPredicate(format: "title contains[cd] %@", fi))
				orPredicates.append(NSPredicate(format: "userLogin contains[cd] %@", fi))
				if Settings.includeReposInFilter {
					orPredicates.append(NSPredicate(format: "repo.fullName contains[cd] %@", fi))
				}
				if Settings.includeLabelsInFilter {
					orPredicates.append(NSPredicate(format: "any labels.name contains[cd] %@", fi))
				}
				andPredicates.append(NSCompoundPredicate.orPredicateWithSubpredicates(orPredicates))
			}
		}

		if Settings.shouldHideUncommentedRequests {
			andPredicates.append(NSPredicate(format: "unreadComments > 0"))
		}

		var sortDescriptiors = [NSSortDescriptor]()
		sortDescriptiors.append(NSSortDescriptor(key: "sectionIndex", ascending: true))
		if Settings.groupByRepo {
			sortDescriptiors.append(NSSortDescriptor(key: "repo.fullName", ascending: true, selector: Selector("caseInsensitiveCompare:")))
		}

		if let fieldName = sortField() {
			if fieldName == "title" {
				sortDescriptiors.append(NSSortDescriptor(key: fieldName, ascending: !Settings.sortDescending, selector: Selector("caseInsensitiveCompare:")))
			} else if !fieldName.isEmpty {
				sortDescriptiors.append(NSSortDescriptor(key: fieldName, ascending: !Settings.sortDescending))
			}
		}

		let f = NSFetchRequest(entityName: "Issue")
		f.fetchBatchSize = 100
		f.predicate = NSCompoundPredicate.andPredicateWithSubpredicates(andPredicates)
		f.sortDescriptors = sortDescriptiors
		return f
	}

	class func sortField() -> String? {
		switch (Settings.sortMethod) {
		case PRSortingMethod.CreationDate.rawValue: return "createdAt"
		case PRSortingMethod.RecentActivity.rawValue: return "updatedAt"
		case PRSortingMethod.Title.rawValue: return "title"
		default: return nil
		}
	}

	class func countAllIssuesInMoc(moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest(entityName: "Issue")
		f.predicate = NSPredicate(format: "sectionIndex > 0")
		return moc.countForFetchRequest(f, error: nil)
	}

	class func countIssuesInSection(section: Int, moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest(entityName: "Issue")
		f.predicate = NSPredicate(format: "sectionIndex == %d", section)
		return moc.countForFetchRequest(f, error: nil)
	}

	class func badgeCountInMoc(moc: NSManagedObjectContext) -> Int {
		let f = requestForIssuesWithFilter(nil, sectionIndex: -1)
		var badgeCount:Int = 0
		let showCommentsEverywhere = Settings.showCommentsEverywhere
		for i in moc.executeFetchRequest(f, error: nil) as! [Issue] {
			if let sectionIndex = i.sectionIndex?.integerValue {
				if showCommentsEverywhere || sectionIndex==PullRequestSection.Mine.rawValue || sectionIndex==PullRequestSection.Participated.rawValue {
					if let c = i.unreadComments?.integerValue {
						badgeCount += c
					}
				}
			}
		}
		return badgeCount
	}

	class func badgeCountInSection(section: Int, moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest(entityName: "Issue")
		f.predicate = NSPredicate(format: "sectionIndex == %d", section)
		var badgeCount:Int = 0
		let showCommentsEverywhere = Settings.showCommentsEverywhere
		for p in moc.executeFetchRequest(f, error: nil) as! [Issue] {
			if let sectionIndex = p.sectionIndex?.integerValue {
				if showCommentsEverywhere || sectionIndex==PullRequestSection.Mine.rawValue || sectionIndex==PullRequestSection.Participated.rawValue {
					if let c = p.unreadComments?.integerValue {
						badgeCount += c
					}
				}
			}
		}
		return badgeCount
	}

	class func countOpenIssuesInMoc(moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest(entityName: "Issue")
		f.predicate = NSPredicate(format: "condition == %d or condition == nil", PullRequestCondition.Open.rawValue)
		return moc.countForFetchRequest(f, error: nil)
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

	func subtitleWithFont(font: FONT_CLASS, lightColor: COLOR_CLASS, darkColor: COLOR_CLASS) -> NSMutableAttributedString {
		let _subtitle = NSMutableAttributedString()
		let p = NSMutableParagraphStyle()
		#if os(iOS)
			p.lineHeightMultiple = 1.3
		#endif

		let lightSubtitle = [NSForegroundColorAttributeName: lightColor, NSFontAttributeName:font, NSParagraphStyleAttributeName: p]

		#if os(iOS)
			let separator = NSAttributedString(string:"\n", attributes:lightSubtitle)
		#elseif os(OSX)
			let separator = NSAttributedString(string:"   ", attributes:lightSubtitle)
		#endif

		if Settings.showReposInName {
			if let n = repo.fullName {
				var darkSubtitle = lightSubtitle
				darkSubtitle[NSForegroundColorAttributeName] = darkColor
				_subtitle.appendAttributedString(NSAttributedString(string:n, attributes:darkSubtitle))
				_subtitle.appendAttributedString(separator)
			}
		}

		if let l = userLogin {
			_subtitle.appendAttributedString(NSAttributedString(string: "@"+l, attributes: lightSubtitle))
			_subtitle.appendAttributedString(separator)
		}

		if Settings.showCreatedInsteadOfUpdated {
			_subtitle.appendAttributedString(NSAttributedString(string: itemDateFormatter.stringFromDate(createdAt!), attributes: lightSubtitle))
		} else {
			_subtitle.appendAttributedString(NSAttributedString(string: itemDateFormatter.stringFromDate(updatedAt!), attributes: lightSubtitle))
		}
		
		return _subtitle
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

	func sectionName() -> String {
		return PullRequestSection.prMenuTitles[sectionIndex?.integerValue ?? 0]
	}

	func postProcess() {
		var section: Int
		var currentCondition = condition?.integerValue ?? PullRequestCondition.Open.rawValue

		if currentCondition == PullRequestCondition.Merged.rawValue			{ section = PullRequestSection.Merged.rawValue }
		else if currentCondition == PullRequestCondition.Closed.rawValue	{ section = PullRequestSection.Closed.rawValue }
		else if isMine()													{ section = PullRequestSection.Mine.rawValue }
		else if commentedByMe()												{ section = PullRequestSection.Participated.rawValue }
		else if Settings.hideAllPrsSection									{ section = PullRequestSection.None.rawValue }
		else																{ section = PullRequestSection.All.rawValue }

		var needsManualCount = false
		var moveToParticipated = false
		let outsideMySections = (section == PullRequestSection.All.rawValue || section == PullRequestSection.None.rawValue)

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
			section = PullRequestSection.Participated.rawValue
			f.predicate = predicateForOthersCommentsSinceDate(latestDate)
			unreadComments = managedObjectContext?.countForFetchRequest(f, error: nil)
		} else if needsManualCount {
			f.predicate = predicateForOthersCommentsSinceDate(nil)
			var unreadCommentCount: Int = 0
			for c in managedObjectContext?.executeFetchRequest(f, error: nil) as! [PRComment] {
				if c.refersToMe() {
					section = PullRequestSection.Participated.rawValue
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

		sectionIndex = section
		totalComments = comments.count

		if title==nil { title = "(No title)" }
	}

	func predicateForOthersCommentsSinceDate(optionalDate: NSDate?) -> NSPredicate {
		var userNumber = apiServer.userId?.longLongValue ?? 0
		if let date = optionalDate {
			return NSPredicate(format: "userId != %lld and issue == %@ and createdAt > %@", userNumber, self, date)
		} else {
			return NSPredicate(format: "userId != %lld and issue == %@", userNumber, self)
		}
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

	class func allClosedIssuesInMoc(moc: NSManagedObjectContext) -> [Issue] {
		let f = NSFetchRequest(entityName: "Issue")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "condition == %d", PullRequestCondition.Closed.rawValue)
		return moc.executeFetchRequest(f, error: nil) as! [Issue]
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

	func accessibleSubtitle() -> String {
		var components = [String]()

		if Settings.showReposInName {
			let repoFullName = repo.fullName ?? "NoRepoFullName"
			components.append("Repository: \(repoFullName)")
		}

		if let l = userLogin { components.append("Author: \(l)") }

		if Settings.showCreatedInsteadOfUpdated {
			components.append("Created \(itemDateFormatter.stringFromDate(createdAt!))")
		} else {
			components.append("Updated \(itemDateFormatter.stringFromDate(updatedAt!))")
		}

		return ",".join(components)
	}
}
