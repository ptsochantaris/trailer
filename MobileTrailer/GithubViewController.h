
@interface GithubViewController : UIViewController <WKNavigationDelegate>

@property (nonatomic) WKWebView *webView;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *spinner;
@property (nonatomic) NSString *pathToLoad;

@end
