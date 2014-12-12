
@class PullRequest;

@interface PRItemView : NSTableCellView

@property (nonatomic) BOOL selected;

- (instancetype)initWithPullRequest:(PullRequest *)pullRequest;

- (PullRequest *)associatedPullRequest;

- (NSString *)stringForCopy;

@end
