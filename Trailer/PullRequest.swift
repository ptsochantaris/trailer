
let itemDateFormatter = createItemDateFormatter()

func createItemDateFormatter() -> NSDateFormatter {
	let f = NSDateFormatter()
	f.doesRelativeDateFormatting = true
	f.dateStyle = NSDateFormatterStyle.MediumStyle
	f.timeStyle = NSDateFormatterStyle.ShortStyle
	return f
}

@objc (PullRequest)
class PullRequest: DataItem {

    @NSManaged var assignedToMe: NSNumber?
    @NSManaged var body: String?
    @NSManaged var condition: NSNumber?
    @NSManaged var isNewAssignment: NSNumber?
    @NSManaged var issueCommentLink: String?
    @NSManaged var issueUrl: String?
    @NSManaged var latestReadCommentDate: NSDate?
    @NSManaged var mergeable: NSNumber?
    @NSManaged var number: NSNumber?
    @NSManaged var pinned: NSNumber?
    @NSManaged var reopened: NSNumber?
    @NSManaged var repoName: String?
    @NSManaged var reviewCommentLink: String?
    @NSManaged var sectionIndex: NSNumber?
    @NSManaged var state: String?
    @NSManaged var statusesLink: String?
    @NSManaged var title: String?
    @NSManaged var totalComments: NSNumber?
    @NSManaged var unreadComments: NSNumber?
    @NSManaged var url: String?
    @NSManaged var userAvatarUrl: String?
    @NSManaged var userId: NSNumber?
    @NSManaged var userLogin: String?
    @NSManaged var webUrl: String?

    @NSManaged var comments: NSSet
    @NSManaged var labels: NSSet
    @NSManaged var repo: Repo
    @NSManaged var statuses: NSSet

	class func pullRequestWithInfo(info: NSDictionary, fromServer: ApiServer) -> PullRequest {
		let p = DataItem.itemWithInfo(info, type: "PullRequest", fromServer: fromServer) as PullRequest
		if p.postSyncAction?.integerValue != PostSyncAction.DoNothing.rawValue {
			p.url = info.ofk("url") as String?
			p.webUrl = info.ofk("html_url") as String?
			p.number = info.ofk("number") as NSNumber?
			p.state = info.ofk("state") as String?
			p.title = info.ofk("title") as String?
			p.body = info.ofk("body") as String?

			if let m = info.ofk("mergeable") as NSNumber? {
				p.mergeable = m
			} else {
				p.mergeable = true
			}

			if let userInfo = info.ofk("user") as NSDictionary? {
				p.userId = userInfo.ofk("id") as NSNumber?
				p.userLogin = userInfo.ofk("login") as String?
				p.userAvatarUrl = userInfo.ofk("avatar_url") as String?
			}

			if let linkInfo = info.ofk("_links") as NSDictionary? {
				p.issueCommentLink = (linkInfo.ofk("comments") as NSDictionary?)?.ofk("href") as String?
				p.reviewCommentLink = (linkInfo.ofk("review_comments") as NSDictionary?)?.ofk("href") as String?
				p.statusesLink = (linkInfo.ofk("statuses") as NSDictionary?)?.ofk("href") as String?
				p.issueUrl = (linkInfo.ofk("issue") as NSDictionary?)?.ofk("href") as String?
			}
		}

		if let c = p.condition {
			p.reopened = (c.intValue == kPullRequestConditionClosed)
		} else {
			p.reopened = false
		}
		p.condition = Int(kPullRequestConditionOpen)

		return p;
	}

	class func sortField() -> String? {
		switch (settings.sortMethod) {
		case PRSortingMethod.CreationDate.rawValue: return "createdAt"
		case PRSortingMethod.RecentActivity.rawValue: return "updatedAt"
		case PRSortingMethod.Title.rawValue: return "title"
		default: return nil
		}
	}

	class func requestForPullRequestsWithFilter(filter: String?) -> NSFetchRequest {

		var predicateSegments = [String]()
		predicateSegments.append("(sectionIndex > 0)")

		if let f = filter {
			if f.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) > 0 {
				if settings.includeReposInFilter {
					predicateSegments.append("(title contains[cd] '\(f)' or userLogin contains[cd] '\(f)' or repoName contains[cd] '\(f)')")
				} else {
					predicateSegments.append("(title contains[cd] '\(f)' or userLogin contains[cd] '\(f)'")
				}
			}
		}

		if settings.shouldHideUncommentedRequests {
			predicateSegments.append("(unreadComments > 0)")
		}

		var sortDescriptiors = [NSSortDescriptor]()
		sortDescriptiors.append(NSSortDescriptor(key: "sectionIndex", ascending: true))

		if settings.groupByRepo {
			sortDescriptiors.append(NSSortDescriptor(key: "repoName", ascending: true, selector: Selector("caseInsensitiveCompare:")))
		}

		if let fieldName = sortField() {
			if fieldName == "title" {
				sortDescriptiors.append(NSSortDescriptor(key: fieldName, ascending: !settings.sortDescending, selector: Selector("caseInsensitiveCompare:")))
			} else if fieldName.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) > 0 {
				sortDescriptiors.append(NSSortDescriptor(key: fieldName, ascending: !settings.sortDescending))
			}
		}

		let f = NSFetchRequest(entityName: "PullRequest")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: " and ".join(predicateSegments))
		f.sortDescriptors = sortDescriptiors
		return f
	}

	class func allMergedRequestsInMoc(moc: NSManagedObjectContext) -> [PullRequest] {
		let f = NSFetchRequest(entityName: "PullRequest")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "condition == %d", kPullRequestConditionMerged)
		return moc.executeFetchRequest(f, error: nil) as [PullRequest]
	}

	class func allClosedRequestsInMoc(moc: NSManagedObjectContext) -> [PullRequest] {
		let f = NSFetchRequest(entityName: "PullRequest")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "condition == %d", kPullRequestConditionClosed)
		return moc.executeFetchRequest(f, error: nil) as [PullRequest]
	}

	class func countOpenRequestsInMoc(moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest(entityName: "PullRequest")
		f.predicate = NSPredicate(format: "condition == %d or condition == nil", kPullRequestConditionOpen)
		return moc.countForFetchRequest(f, error: nil)
	}

	class func badgeCountInMoc(moc: NSManagedObjectContext) -> Int {
		let f = requestForPullRequestsWithFilter(nil)
		var badgeCount:Int = 0
		let showCommentsEverywhere = settings.showCommentsEverywhere
		for p in moc.executeFetchRequest(f, error: nil) as [PullRequest] {
			if let sectionIndex = p.sectionIndex?.intValue {
				if showCommentsEverywhere || sectionIndex==kPullRequestSectionMine || sectionIndex==kPullRequestSectionParticipated {
					if let c = p.unreadComments?.integerValue {
						badgeCount += c
					}
				}
			}
		}
		return badgeCount;
	}

	func catchUpWithComments() {
		for c in comments.allObjects as [PRComment] {
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
			if assigned && settings.moveAssignedPrsToMySection {
				return true
			}
		}
		if let userId = self.userId {
			if let apiId = self.apiServer.userId {
				return userId == apiId
			}
		}
		return false
	}

	func refersToMe() -> Bool {
		if let apiName = self.apiServer.userName {
			if let b = body {
				let range = b.rangeOfString("@"+apiName,
					options: NSStringCompareOptions.CaseInsensitiveSearch | NSStringCompareOptions.DiacriticInsensitiveSearch)
				return range != nil
			}
		}
		return false
	}

	func commentedByMe() -> Bool {
		for c in comments.allObjects as [PRComment] {
			if c.isMine() {
				return true
			}
		}
		return false
	}

	func markUnmergeable() -> Bool {
		if let m = mergeable?.boolValue {
			if !m {
				if let s = sectionIndex?.intValue {
					if s == kPullRequestConditionMerged || s == kPullRequestConditionClosed {
						return false
					}
					if s == kPullRequestSectionAll && settings.markUnmergeableOnUserSectionsOnly {
						return false
					}
					return true
				}
			}
		}
		return false
	}

	func titleWithFont(font: FONT_CLASS, labelFont: FONT_CLASS, titleColor: COLOR_CLASS) -> NSMutableAttributedString {
		let p = NSMutableParagraphStyle()
		p.paragraphSpacing = 1.0

		let titleAttributes = [NSFontAttributeName: font, NSForegroundColorAttributeName: titleColor, NSParagraphStyleAttributeName: p]
		let _title = NSMutableAttributedString()
		if let t = title {
			_title.appendAttributedString(NSAttributedString(string: t, attributes: titleAttributes))
			if settings.showLabels {
				var allLabels = labels.allObjects as [PRLabel]
				if allLabels.count > 0 {

					_title.appendAttributedString(NSAttributedString(string: "\n", attributes: titleAttributes))

					let lp = NSMutableParagraphStyle()
					#if os(iOS)
						lp.lineHeightMultiple = 1.15;
						let labelAttributes = [NSFontAttributeName: labelFont,
						NSBackgroundColorAttributeName: COLOR_CLASS.clearColor(),
						NSBaselineOffsetAttributeName: 2.0,
						NSParagraphStyleAttributeName: lp]
						#elseif os(OSX)
						lp.minimumLineHeight = labelFont.pointSize+6.0;
						let labelAttributes = [NSFontAttributeName: labelFont,
							NSBackgroundColorAttributeName: COLOR_CLASS.clearColor(),
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
						a[NSBackgroundColorAttributeName] = color;
						a[NSForegroundColorAttributeName] = isDarkColor(color) ? COLOR_CLASS.whiteColor() : COLOR_CLASS.blackColor();
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

	func isDarkColor(color: COLOR_CLASS) -> Bool {
		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0;
		color.getRed(&r, green: &g, blue: &b, alpha: nil)
		let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
		return (lum < 0.5);
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

		if settings.showReposInName {
			if let n = repoName {
				var darkSubtitle = lightSubtitle;
				darkSubtitle[NSForegroundColorAttributeName] = darkColor
				_subtitle.appendAttributedString(NSAttributedString(string:n, attributes:darkSubtitle));
				_subtitle.appendAttributedString(separator)
			}
		}

		if let l = userLogin {
			_subtitle.appendAttributedString(NSAttributedString(string: "@"+l, attributes: lightSubtitle))
			_subtitle.appendAttributedString(separator)
		}

		if settings.showCreatedInsteadOfUpdated {
			_subtitle.appendAttributedString(NSAttributedString(string: itemDateFormatter.stringFromDate(createdAt!), attributes: lightSubtitle))
		} else {
			_subtitle.appendAttributedString(NSAttributedString(string: itemDateFormatter.stringFromDate(updatedAt!), attributes: lightSubtitle))
		}

		#if os(iOS)
		if let m = mergeable?.boolValue {
			if !m {
				_subtitle.appendAttributedString(separator)
				var redSubtitle = lightSubtitle
				redSubtitle[NSForegroundColorAttributeName] = COLOR_CLASS.redColor();
				_subtitle.appendAttributedString(NSAttributedString(string: "Cannot be merged!", attributes:redSubtitle))
			}
		}
		#endif

		return _subtitle
	}

	func accessibleTitle() -> String {
		var components = [String]()
		if let t = title { components.append(t) }
		if settings.showLabels {
			var allLabels = labels.allObjects as [PRLabel]
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

		if(settings.showReposInName) { components.append("Repository: \(self.repoName)") }

		if let l = userLogin { components.append("Author: \(l)") }

		if(settings.showCreatedInsteadOfUpdated) {
			components.append("Created \(itemDateFormatter.stringFromDate(createdAt!))")
		} else {
			components.append("Updated \(itemDateFormatter.stringFromDate(updatedAt!))")
		}

		if let m = mergeable?.boolValue {
			if !m {
				components.append("Cannot be merged!")
			}
		}

		return ",".join(components)
	}

	func displayedStatuses() -> [PRStatus] {
		let f = NSFetchRequest(entityName: "PRStatus")
		f.returnsObjectsAsFaults = false
		let mode = Int32(settings.statusFilteringMode)
		if mode==kStatusFilterAll {
			f.predicate = NSPredicate(format: "pullRequest == %@", self)
		} else {
			let terms = settings.statusFilteringTerms as [String]?;
			if(terms != nil && terms!.count > 0)
			{
				var subPredicates = [NSPredicate]()
				for t in terms! {
					subPredicates.append(NSPredicate(format: "descriptionText contains[cd] %@", t)!)
				}
				let orPredicate = NSCompoundPredicate.orPredicateWithSubpredicates(subPredicates);
				let selfPredicate = NSPredicate(format: "pullRequest == %@", self)!

				if(mode==kStatusFilterInclude)
				{
					f.predicate = NSCompoundPredicate.andPredicateWithSubpredicates([selfPredicate, orPredicate])
				}
				else
				{
					let notOrPredicate = NSCompoundPredicate.notPredicateWithSubpredicate(orPredicate)
					f.predicate = NSCompoundPredicate.andPredicateWithSubpredicates([selfPredicate, notOrPredicate])
				}
			}
			else
			{
				f.predicate = NSPredicate(format: "pullRequest == %@", self)
			}
		}
		f.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

		var result = [PRStatus]()
		let targetUrls = NSMutableSet()
		let descriptions = NSMutableSet()
		for s in self.managedObjectContext?.executeFetchRequest(f, error: nil) as [PRStatus] {
			var targetUrl: String
			if let t = s.targetUrl { targetUrl = t } else { targetUrl = "" }
			var desc: String
			if let d = s.descriptionText { desc = d } else { desc = "(No status description)" }

			if !descriptions.containsObject(desc) {
				descriptions.addObject(desc)
				if !targetUrls.containsObject(targetUrl) {
					targetUrls.addObject(targetUrl)
					result.append(s)
				}
			}
		}
		return result
	}

	func urlForOpening() -> String? {
		var unreadCount = 0
		if let c = self.unreadComments?.integerValue {
			unreadCount = c
		}

		if(unreadCount > 0 && settings.openPrAtFirstUnreadComment) {
			let f = NSFetchRequest(entityName: "PRComment")
			f.returnsObjectsAsFaults = false
			f.fetchLimit = 1
			f.predicate = predicateForOthersCommentsSinceDate(latestReadCommentDate)
			f.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
			let ret = managedObjectContext?.executeFetchRequest(f, error: nil) as [PRComment]
			if let firstComment = ret.first {
				if let url = firstComment.webUrl {
					return url
				}
			}
		}

		return webUrl
	}

	func labelsLink() -> String {
		return self.issueUrl!.stringByAppendingPathComponent("labels");
	}

	func sectionName() -> String {
		return kPullRequestSectionNames[self.sectionIndex!.integerValue]
	}

	func postProcess() {
		var section: Int32
		var condition = kPullRequestConditionOpen

		if let c = self.condition?.intValue {
			condition = c
		}

		if condition == kPullRequestConditionMerged			{ section = kPullRequestSectionMerged }
		else if condition == kPullRequestConditionClosed	{ section = kPullRequestConditionClosed }
		else if isMine()									{ section = kPullRequestSectionMine }
		else if commentedByMe()								{ section = kPullRequestSectionParticipated }
		else if settings.hideAllPrsSection					{ section = kPullRequestSectionNone }
		else												{ section = kPullRequestSectionAll }

		let f = NSFetchRequest(entityName: "PRComment")
		f.returnsObjectsAsFaults = false

		let latestDate = self.latestReadCommentDate;
		if (section == kPullRequestSectionAll || section == kPullRequestSectionNone) && settings.autoParticipateInMentions {
			if refersToMe() {
				section = kPullRequestSectionParticipated;
				f.predicate = predicateForOthersCommentsSinceDate(latestDate)
				let count = self.managedObjectContext?.countForFetchRequest(f, error: nil)
				self.unreadComments = count!
			} else {
				f.predicate = predicateForOthersCommentsSinceDate(nil)
				var unreadCommentCount: Int = 0
				for c in self.managedObjectContext?.executeFetchRequest(f, error: nil) as [PRComment] {
					if c.refersToMe() {
						section = kPullRequestSectionParticipated
					}
					if let l = latestDate {
						if c.createdAt?.compare(l)==NSComparisonResult.OrderedDescending {
							unreadCommentCount++
						}
					}
				}
				self.unreadComments = unreadCommentCount
			}
		} else {
			f.predicate = predicateForOthersCommentsSinceDate(latestDate)
			let count = self.managedObjectContext?.countForFetchRequest(f, error: nil)
			self.unreadComments = count!
		}

		self.sectionIndex = Int(section)
		self.totalComments = self.comments.count
		self.repoName = self.repo.fullName

		if self.title==nil { self.title = "(No title)" }
	}

	func predicateForOthersCommentsSinceDate(optionalDate: NSDate?) -> NSPredicate {
		var userNumber: Int64
		if let lld = apiServer.userId?.longLongValue {
			userNumber = lld
		} else {
			userNumber = 0
		}
		if let date = optionalDate {
			return NSPredicate(format: "userId != %lld and pullRequest == %@ and createdAt > %@", userNumber, self, date)!
		} else {
			return NSPredicate(format: "userId != %lld and pullRequest == %@", userNumber, self)!
		}
	}
}
