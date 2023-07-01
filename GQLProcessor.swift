import AsyncAlgorithms
import Foundation

extension GraphQL {
    final class Processor {
        struct Chunk {
            let nodes: [String: LinkedList<Node>]
            let server: ApiServer
            let parentType: ListableItem.Type?
            let moreComing: Bool

            var report: String {
                var components = [String]()
                for (type, list) in nodes {
                    components.append("\(type): \(list.count)")
                }
                if moreComing {
                    components.append("more coming")
                }
                return components.joined(separator: ", ")
            }
        }

        private let queue = AsyncChannel<Chunk>()

        private var ingest: Task<Void, Never>?

        init() {
            ingest = Task.detached { [weak self] in
                guard let self else { return }
                for await chunk in queue {
                    DLog("Processing GQL nodes: \(chunk.report)")
                    await process(chunk: chunk)
                    if !chunk.moreComing {
                        queue.finish()
                    }
                }
            }
        }

        func waitForCompletion() async {
            await ingest?.value
        }

        func add(chunk: Chunk) {
            Task {
                await queue.send(chunk)
            }
        }

        private func process(chunk: Chunk) async {
            guard chunk.nodes.count > 0, let moc = chunk.server.managedObjectContext else { return }
            await DataManager.runInChild(of: moc) { child in
                guard let server = try? child.existingObject(with: chunk.server.objectID) as? ApiServer else {
                    return
                }

                let parentCache = FetchCache()
                // Order must be fixed, since labels may refer to PRs or Issues, ensure they are created first

                if let nodeList = chunk.nodes["Repository"] {
                    Repo.sync(from: nodeList, on: server, moc: child, parentCache: parentCache)
                }
                if let nodeList = chunk.nodes["Issue"] {
                    Issue.sync(from: nodeList, on: server, moc: child, parentCache: parentCache)
                }
                if let nodeList = chunk.nodes["PullRequest"] {
                    PullRequest.sync(from: nodeList, on: server, moc: child, parentCache: parentCache)
                }
                if let nodeList = chunk.nodes["Label"] {
                    PRLabel.sync(from: nodeList, on: server, moc: child, parentCache: parentCache)
                }
                if let nodeList = chunk.nodes["CommentReaction"] {
                    Reaction.sync(from: nodeList, for: PRComment.self, on: server, moc: child, parentCache: parentCache)
                }
                if let nodeList = chunk.nodes["IssueComment"] {
                    PRComment.sync(from: nodeList, on: server, moc: child, parentCache: parentCache)
                }
                if let nodeList = chunk.nodes["PullRequestReviewComment"] {
                    PRComment.sync(from: nodeList, on: server, moc: child, parentCache: parentCache)
                }
                if let nodeList = chunk.nodes["Reaction"], let parentType = chunk.parentType {
                    Reaction.sync(from: nodeList, for: parentType, on: server, moc: child, parentCache: parentCache)
                }
                if let nodeList = chunk.nodes["ReviewRequest"] {
                    Review.syncRequests(from: nodeList, moc: child, parentCache: parentCache)
                }
                if let nodeList = chunk.nodes["PullRequestReview"] {
                    Review.sync(from: nodeList, on: server, moc: child, parentCache: parentCache)
                }
                if let nodeList = chunk.nodes["StatusContext"] {
                    PRStatus.sync(from: nodeList, on: server, moc: child, parentCache: parentCache)
                }
                if let nodeList = chunk.nodes["CheckRun"] {
                    PRStatus.sync(from: nodeList, on: server, moc: child, parentCache: parentCache)
                }
            }
        }
    }
}
