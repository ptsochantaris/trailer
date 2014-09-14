
@interface DetailViewController : UIViewController
<UISplitViewControllerDelegate, UIWebViewDelegate, NSURLConnectionDataDelegate>

@property (strong, nonatomic) NSURL *detailItem;

@property (weak, nonatomic) IBOutlet UIWebView *web;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *spinner;
@property (weak, nonatomic) IBOutlet UILabel *statusLabel;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *shareButton;
@property (weak, nonatomic) IBOutlet UIButton *tryAgainButton;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *pullRequestsButton;

+ (DetailViewController *)shared;

@end
