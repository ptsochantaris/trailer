
@interface GithubViewController () <UIWebViewDelegate>

@end

@implementation GithubViewController

- (void)viewDidLoad
{
	[super viewDidLoad];
	[self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:self.pathToLoad]]];
}

- (void)webViewDidStartLoad:(UIWebView *)webView
{
	self.webView.hidden = YES;
	[self.spinner startAnimating];
}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
	self.webView.hidden = NO;
	[self.spinner stopAnimating];
}

@end
