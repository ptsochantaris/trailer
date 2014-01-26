
@implementation EmptyView

- (id)initWithFrame:(NSRect)frameRect message:(NSAttributedString *)message
{
	self = [super initWithFrame:frameRect];
	if(self)
	{
		CenteredTextField *text = [[CenteredTextField alloc] initWithFrame:CGRectInset(self.bounds, MENU_WIDTH*0.13, 0)];
		[text setAttributedStringValue:message];
		[self addSubview:text];
	}
	return self;
}

@end
