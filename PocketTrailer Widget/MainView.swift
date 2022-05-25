//
//  MainView.swift
//  Trailer
//
//  Created by Paul Tsochantaris on 24/05/2022.
//

import SwiftUI

struct SectionView: View {
    let section: Section
    let count: Int
    var body: some View {
        // normalAttributes
        Text("\(count)\u{a0}\(section.watchMenuName), ")
    }
}

struct CommentCount: View {
    let count: Int
    var body: some View {
        if count > 1 {
            Text("\(count)\u{a0}unread\u{a0}comments").font(.caption).foregroundColor(.red)
        } else if count == 1 {
            Text("1\u{a0}unread\u{a0}comment").font(.caption).foregroundColor(.red)
        } else {
            Text("No\u{a0}unread\u{a0}comments").font(.caption).foregroundColor(Color("dimText"))
        }
    }
}

struct TypeSection: View {
    let type: String
    
    private var totalOpen = 0
    private var totalUnread = 0
    private var totalMine = 0
    private var totalParticipated = 0
    private var totalMentioned = 0
    private var totalSnoozed = 0
    private var totalMerged = 0
    private var totalClosed = 0
    private var totalOther = 0
    private var error: String
    
    init(type: String, info: [AnyHashable: Any]) {
        self.type = type

        error = info["error"] as? String ?? "No items"
        
        for r in info["views"] as! [[AnyHashable : Any]] {
            if let v = r[type] as? [AnyHashable : Any] {
                totalMine += (v[Section.mine.apiName] as? [AnyHashable : Any])?["total"] as? Int ?? 0
                totalParticipated += (v[Section.participated.apiName] as? [AnyHashable : Any])?["total"] as? Int ?? 0
                totalMentioned += (v[Section.mentioned.apiName] as? [AnyHashable : Any])?["total"] as? Int ?? 0
                totalSnoozed += (v[Section.snoozed.apiName] as? [AnyHashable : Any])?["total"] as? Int ?? 0
                totalOther += (v[Section.all.apiName] as? [AnyHashable : Any])?["total"] as? Int ?? 0
                totalMerged += (v[Section.merged.apiName] as? [AnyHashable : Any])?["total"] as? Int ?? 0
                totalClosed += (v[Section.closed.apiName] as? [AnyHashable : Any])?["total"] as? Int ?? 0
                totalUnread += v["unread"] as? Int ?? 0
                totalOpen += v["total_open"] as? Int ?? 0
            }
        }
    }

    var body: some View {
        let totalCount = totalMerged+totalMine+totalParticipated+totalClosed+totalMentioned+totalSnoozed+totalOther

        if totalCount > 0 {
            // titleAttributes
            HStack {
                Text("\(totalCount): ").font(.caption)
                CommentCount(count: totalUnread)
            }
            //if extensionContext?.widgetActiveDisplayMode == .compact {
//            } else {
//                append(a, count: totalMine, section: .mine)
//                append(a, count: totalParticipated, section: .participated)
//                append(a, count: totalMentioned, section: .mentioned)
//                append(a, count: totalMerged, section: .merged)
//                append(a, count: totalClosed, section: .closed)
//                append(a, count: totalOther, section: .all)
//                append(a, count: totalSnoozed, section: .snoozed)
//                appendCommentCount(a, number: totalUnread)
//            }
        } else {
            // titleAttributes
            Text("Error: \(error)").font(.headline)
        }
    }
}

struct MainView : View {
    var entry: Summary
    
    var body: some View {
        let imageSize = 18
        if let result = entry.data {
            VStack(spacing: 16) {
                HStack(alignment: .top) {
                    Image("prsTab").resizable().scaledToFit().frame(width: imageSize, height: imageSize)
                    TypeSection(type: "prs", info: result)
                }
                HStack(alignment: .top) {
                    Image("issuesTab").resizable().scaledToFit().frame(width: imageSize, height: imageSize)
                    TypeSection(type: "issues", info: result)
                }
                let updated = agoFormat(prefix: "updated", since: result["lastUpdated"] as? Date).capitalFirstLetter
                Text(updated).font(.caption2).foregroundColor(Color("dimText"))
            }
            
        } else {
            VStack(spacing: 16) {
                HStack(alignment: .top) {
                    Image("prsTab").resizable().scaledToFit().frame(width: imageSize, height: imageSize)
                    Text("--").font(.caption).foregroundColor(Color("dimText"))
                }
                HStack(alignment: .top) {
                    Image("issuesTab").resizable().scaledToFit().frame(width: imageSize, height: imageSize)
                    Text("--").font(.caption).foregroundColor(Color("dimText"))
                }
                Text("Not updated yet").font(.caption2).foregroundColor(Color("dimText"))
            }
        }
    }
}
