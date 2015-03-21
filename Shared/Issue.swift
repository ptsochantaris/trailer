//
//  Issue.swift
//  Trailer
//
//  Created by Paul Tsochantaris on 21/03/2015.
//
//

import CoreData

@objc (Issue)
class Issue: DataItem {

    @NSManaged var body: String?
	@NSManaged var webUrl: String?
	@NSManaged var title: String?
	@NSManaged var sectionIndex: NSNumber?
	@NSManaged var totalComments: NSNumber?
	@NSManaged var unreadComments: NSNumber?
	@NSManaged var condition: NSNumber?

	@NSManaged var labels: NSSet
	@NSManaged var comments: NSSet
	@NSManaged var repo: Repo

	class func requestForIssuesWithFilter(filter: String?) -> NSFetchRequest {
		return requestForIssuesWithFilter(filter, sectionIndex: -1)
	}

	class func requestForIssuesWithFilter(filter: String?, sectionIndex: Int) -> NSFetchRequest {

		var andPredicates = [NSPredicate]()
		if sectionIndex<0 {
			andPredicates.append(NSPredicate(format: "sectionIndex > 0")!)
		} else {
			andPredicates.append(NSPredicate(format: "sectionIndex == %d", sectionIndex)!)
		}

		if let fi = filter {
			if !fi.isEmpty {

				var orPredicates = [NSPredicate]()
				orPredicates.append(NSPredicate(format: "title contains[cd] %@", fi)!)
				orPredicates.append(NSPredicate(format: "userLogin contains[cd] %@", fi)!)
				if Settings.includeReposInFilter {
					orPredicates.append(NSPredicate(format: "repo.fullName contains[cd] %@", fi)!)
				}
				if Settings.includeLabelsInFilter {
					orPredicates.append(NSPredicate(format: "any labels.name contains[cd] %@", fi)!)
				}
				andPredicates.append(NSCompoundPredicate.orPredicateWithSubpredicates(orPredicates))
			}
		}

		if Settings.shouldHideUncommentedRequests {
			andPredicates.append(NSPredicate(format: "unreadComments > 0")!)
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

	class func badgeCountInMoc(moc: NSManagedObjectContext) -> Int {
		let f = requestForIssuesWithFilter(nil)
		var badgeCount:Int = 0
		let showCommentsEverywhere = Settings.showCommentsEverywhere
		for p in moc.executeFetchRequest(f, error: nil) as [PullRequest] {
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
}
