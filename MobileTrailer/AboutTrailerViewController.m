
@interface AboutTrailerViewController ()

@end

@implementation AboutTrailerViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	self.versionNumber.text = [@"Version " stringByAppendingString:app.currentAppVersion];
}

- (IBAction)ipadLink:(UIBarButtonItem *)sender
{
	NSString *url = @"http://dev.housetrip.com/trailer";
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:url]];
}

- (IBAction)done:(UIBarButtonItem *)sender
{
	if(app.preferencesDirty) [app startRefresh];
	[self dismissViewControllerAnimated:YES completion:nil];
}

@end
