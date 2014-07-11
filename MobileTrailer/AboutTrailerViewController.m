
@interface AboutTrailerViewController ()

@end

@implementation AboutTrailerViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	self.versionNumber.text = [@"Version " stringByAppendingString:[AppDelegate shared].currentAppVersion];
}

- (IBAction)iphoneLink:(UIBarButtonItem *)sender
{
	[self link];
}

- (IBAction)ipadLink:(UIBarButtonItem *)sender
{
	[self link];
}

- (void)link
{
	NSString *url = @"http://dev.housetrip.com/trailer";
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:url]];
}

@end
