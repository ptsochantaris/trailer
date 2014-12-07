#import "AboutTrailerViewController.h"

@implementation AboutTrailerViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	self.versionNumber.text = [@"Version " stringByAppendingString:currentAppVersion];
	self.licenseText.textContainerInset = UIEdgeInsetsMake(0, 10, 10, 10);
}

- (void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];
	self.licenseText.contentOffset = CGPointZero;
}

- (IBAction)ipadLink:(UIBarButtonItem *)sender
{
	NSString *url = @"https://github.com/ptsochantaris/trailer";
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:url]];
}

- (IBAction)done:(UIBarButtonItem *)sender
{
	if(app.preferencesDirty) [app startRefresh];
	[self dismissViewControllerAnimated:YES completion:nil];
}

@end
