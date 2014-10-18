
@implementation DetailViewController

static DetailViewController *_detail_shared_ref;

+ (DetailViewController *)shared
{
	return _detail_shared_ref;
}

#pragma mark - Managing the detail item

- (void)setDetailItem:(id)newDetailItem
{
    if (_detailItem != newDetailItem || self.webView.hidden)
	{
        _detailItem = newDetailItem;
        [self configureView];
    }
}

- (void)configureView
{
	if (self.detailItem)
	{
		DLog(@"will load: %@",self.detailItem.absoluteString);
		[self.webView loadRequest:[NSURLRequest requestWithURL:self.detailItem]];
		self.statusLabel.text = @"";
		self.statusLabel.hidden = YES;
	}
	else
	{
		[self setEmpty];
	}
}

- (void)setEmpty
{
	self.statusLabel.textColor = [COLOR_CLASS lightGrayColor];
	self.statusLabel.text = @"Please select a Pull Request from the list on the left, or select 'Settings' to change your repository selection.\n\n(You may have to login to GitHub the first time you visit a page)";
	self.statusLabel.hidden = NO;
	self.navigationItem.rightBarButtonItem.enabled = NO;
	self.title = nil;
	self.webView.hidden = YES;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	_detail_shared_ref = self;

	WKWebViewConfiguration *webConfiguration = [[WKWebViewConfiguration alloc] init];
	self.webView = [[WKWebView alloc] initWithFrame:self.view.bounds
									  configuration:webConfiguration];
	self.webView.navigationDelegate = self;
	self.webView.scrollView.contentInset = UIEdgeInsetsMake(64, 0, 0, 0);
	self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
	self.webView.translatesAutoresizingMaskIntoConstraints = YES;
	[self.view addSubview:self.webView];

	[self configureView];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
	[super traitCollectionDidChange:previousTraitCollection];

	self.navigationItem.leftBarButtonItem = (self.traitCollection.horizontalSizeClass==UIUserInterfaceSizeClassCompact) ? nil : self.splitViewController.displayModeButtonItem;
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	if(self.webView.isLoading)
		[self.spinner startAnimating];
	else
		[self.spinner stopAnimating];
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation
{
	[self.spinner startAnimating];
	self.statusLabel.hidden = YES;
	self.webView.hidden = YES;
	self.tryAgainButton.hidden = YES;
	self.title = @"Loading...";
	self.navigationItem.rightBarButtonItem = nil;
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler
{
	NSHTTPURLResponse *res = (NSHTTPURLResponse*)navigationResponse.response;
	if(res.statusCode==404)
	{
		[[[UIAlertView alloc] initWithTitle:@"Not Found"
									message:[NSString stringWithFormat:@"\nPlease ensure you are logged in with the '%@' account on GitHub\n\nIf you are using two-factor auth: There is a bug between Github and iOS which may cause your login to fail.  If it happens, temporarily disable two-factor auth and log in from here, then re-enable it afterwards.  You will only need to do this once.",settings.localUser]
								   delegate:nil
						  cancelButtonTitle:@"OK"
						  otherButtonTitles:nil] show];
	}
	decisionHandler(WKNavigationResponsePolicyAllow);
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
	[self.spinner stopAnimating];
	self.statusLabel.hidden = YES;
	self.webView.hidden = NO;
	self.tryAgainButton.hidden = YES;
	self.navigationItem.rightBarButtonItem.enabled = YES;
	self.title = self.webView.title;
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
																						   target:self
																						   action:@selector(shareSelected:)];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
	[self loadFailed:error];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
	[self loadFailed:error];
}

- (void)loadFailed:(NSError *)error
{
	[self.spinner stopAnimating];
	self.statusLabel.textColor = [COLOR_CLASS redColor];
	self.statusLabel.text = [NSString stringWithFormat:@"There was an error loading this pull request page: %@",error.localizedDescription];
	self.statusLabel.hidden = NO;
	self.webView.hidden = YES;
	self.tryAgainButton.hidden = NO;
	self.title = @"Error";
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
																						   target:self
																						   action:@selector(tryAgainSelected:)];
}

- (void)shareSelected:(UIBarButtonItem *)sender
{
	[app shareFromView:self buttonItem:sender url:self.webView.URL];
}

- (void)tryAgainSelected:(UIBarButtonItem *)sender
{
    self.detailItem = self.detailItem;
}

@end
