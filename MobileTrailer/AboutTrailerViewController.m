
@interface AboutTrailerViewController ()

@end

@implementation AboutTrailerViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

	NSString *currentAppVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
	currentAppVersion = [@"Version " stringByAppendingString:currentAppVersion];
	self.versionNumber.text = currentAppVersion;
}

- (IBAction)iphoneLink:(UIBarButtonItem *)sender {
	[self link];
}
- (IBAction)ipadLink:(UIBarButtonItem *)sender {
	[self link];
}
- (void)link
{
	NSString *url = @"http://dev.housetrip.com/trailer";
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:url]];
}

@end
