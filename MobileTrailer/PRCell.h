
@interface PRCell : UITableViewCell

@property (weak, nonatomic) IBOutlet UILabel *label;

- (void)setPullRequest:(PullRequest *)pullRequest;

@end
