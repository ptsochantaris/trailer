@import WebKit;

@interface DetailViewController : UIViewController <WKNavigationDelegate>

@property (strong, nonatomic) NSURL *detailItem;

@property (nonatomic) WKWebView *webView;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *spinner;
@property (weak, nonatomic) IBOutlet UILabel *statusLabel;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *shareButton;
@property (weak, nonatomic) IBOutlet UIButton *tryAgainButton;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *pullRequestsButton;

+ (DetailViewController *)shared;

@end
