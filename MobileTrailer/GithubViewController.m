
@implementation GithubViewController

- (void)viewDidLoad
{
	[super viewDidLoad];

	WKWebViewConfiguration *webConfiguration = [[WKWebViewConfiguration alloc] init];
	self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds
									  configuration:webConfiguration];
	self.webView.navigationDelegate = self;
	self.webView.scrollView.contentInset = UIEdgeInsetsMake(64, 0, 0, 0);
	self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
	self.webView.translatesAutoresizingMaskIntoConstraints = YES;
	[self.view addSubview:self.webView];

	[self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:self.pathToLoad]]];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
	[self loadingFailed];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
	[self loadingFailed];
}

- (void)loadingFailed
{
	self.webView.hidden = NO;
	[self.spinner stopAnimating];
	self.title = @"Loading Failed";
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
	self.webView.hidden = NO;
	[self.spinner stopAnimating];
	self.title = self.webView.title;
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation
{
	self.webView.hidden = YES;
	[self.spinner startAnimating];
}

- (IBAction)ipadDone:(UIBarButtonItem *)sender
{
	[self dismissViewControllerAnimated:YES completion:nil];
}

@end
