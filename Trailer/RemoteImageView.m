
@interface RemoteImageView ()
{
	NSProgressIndicator *spinner;
	NSTimer *patienceTimer;
}
@end

@implementation RemoteImageView

- (id)initWithFrame:(NSRect)frameRect url:(NSString *)urlPath
{
	self = [self initWithFrame:frameRect];
	if(self)
	{
		self.imageAlignment = NSImageAlignCenter;
		self.imageScaling = NSImageScaleProportionallyUpOrDown;

		patienceTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(startSpinner) userInfo:nil repeats:NO];

		[[AppDelegate shared].api getImage:urlPath
								   success:^(NSHTTPURLResponse *response, NSImage *image) {
									   self.image = image;
									   [self done];
								   } failure:^(NSHTTPURLResponse *response, NSError *error) {
									   [self done];
								   }];
	}
	return self;
}

- (void)startSpinner
{
	spinner = [[NSProgressIndicator alloc] initWithFrame:CGRectInset(self.bounds, 6.0, 6.0)];
	spinner.style = NSProgressIndicatorSpinningStyle;
	[self addSubview:spinner];
	[spinner startAnimation:self];
}

- (void)done
{
	[patienceTimer invalidate];
	patienceTimer = nil;

	[spinner stopAnimation:self];
	[spinner removeFromSuperview];
	spinner = nil;
}

@end
