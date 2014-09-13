
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

@end
