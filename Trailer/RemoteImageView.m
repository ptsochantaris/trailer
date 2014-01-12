
@interface RemoteImageView ()
{
	NSProgressIndicator *spinner;
}
@end

@implementation RemoteImageView

- (id)initWithFrame:(NSRect)frameRect url:(NSString *)urlPath
{
	self = [self initWithFrame:frameRect];
	if(self)
	{
		self.imageAlignment = NSImageAlignCenter;
		self.imageScaling = NSImageScaleNone;

        if(![[AppDelegate shared].api haveCachedImage:urlPath
                                              forSize:CGSizeMake(frameRect.size.width, frameRect.size.height)
                                   tryLoadAndCallback:^(id image) {
                                       self.image = image;
                                       [self done];
                                   }])
        {
            [self startSpinner];
        }
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
	[spinner stopAnimation:self];
	[spinner removeFromSuperview];
	spinner = nil;
}

@end
