import Cocoa

extension MenuWindow {
    @MainActor
    final class DataSource: NSObject, NSTableViewDelegate, NSTableViewDataSource {
        private var itemIds = ContiguousArray<Any>()
        private let type: ListableItem.Type
        private let sections: [String]
        private let removalSections: Set<String>
        private let viewCriterion: GroupingCriterion?

        private static let propertiesToFetch = { () -> [NSExpressionDescription] in
            let iodD = NSExpressionDescription()
            iodD.name = "objectID"
            iodD.expression = NSExpression.expressionForEvaluatedObject()
            iodD.expressionResultType = .objectIDAttributeType

            let sectionIndexD = NSExpressionDescription()
            sectionIndexD.name = "si"
            sectionIndexD.expression = NSExpression(format: "sectionIndex")
            sectionIndexD.expressionResultType = .integer16AttributeType

            return [iodD, sectionIndexD]
        }()

        init(type: ListableItem.Type, sections: [String], removeButtonsInSections: [String], viewCriterion: GroupingCriterion?) {
            self.type = type
            self.sections = sections
            removalSections = Set(removeButtonsInSections)
            self.viewCriterion = viewCriterion

            super.init()
        }

        var uniqueIdentifier: String {
            var segments = [String(describing: type)]
            if let viewCriterion {
                segments.append(viewCriterion.label)
                switch viewCriterion {
                case let .server(aid):
                    let uri = aid.uriRepresentation()
                    if let host = uri.host {
                        segments.append(host)
                    }
                    segments.append(uri.path)
                case let .group(name):
                    segments.append(name)
                }
            }
            return segments.joined(separator: "-")
        }

        func reloadData(filter: String?) {
            itemIds.removeAll(keepingCapacity: false)

            let f = ListableItem.requestForItems(of: type, withFilter: filter, sectionIndex: -1, criterion: viewCriterion)
            f.resultType = .dictionaryResultType
            f.fetchBatchSize = 0
            f.propertiesToFetch = DataSource.propertiesToFetch
            let allItems = try! DataManager.main.fetch(f as! NSFetchRequest<NSDictionary>)

            itemIds.reserveCapacity(allItems.count + sections.count)

            var lastSection = -999
            for item in allItems {
                let i = item["si"] as! Int
                if lastSection < i {
                    lastSection = i
                    itemIds.append(sections[i])
                }
                itemIds.append(item["objectID"] as! NSManagedObjectID)
            }
        }

        func tableView(_: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
            let object = itemIds[row]
            if let id = object as? NSManagedObjectID, let i = existingObject(with: id) as? ListableItem {
                return TrailerCell(item: i)
            } else if let title = object as? String {
                return SectionHeader(title: title, showRemoveAllButton: removalSections.contains(title))
            }
            return nil
        }

        func numberOfRows(in _: NSTableView) -> Int {
            itemIds.count
        }

        func itemAtRow(_ row: Int) -> ListableItem? {
            if row >= 0, row < itemIds.count, let id = itemIds[row] as? NSManagedObjectID {
                return existingObject(with: id) as? ListableItem
            } else {
                return nil
            }
        }
    }
}
