
@implementation EmptyView

- (id)initWithFrame:(NSRect)frameRect message:(NSString *)message color:(NSColor *)messageColor
{
	self = [super initWithFrame:frameRect];
	if(self)
	{
		CenteredTextField *text = [[CenteredTextField alloc] initWithFrame:CGRectInset(self.bounds, MENU_WIDTH*0.13, 0)];
		[text setAlignment:NSCenterTextAlignment];
		[text setTextColor:messageColor];
		[text setStringValue:message];
		[self addSubview:text];
	}
	return self;
}

@end
