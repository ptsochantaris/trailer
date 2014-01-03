
@implementation CenteredTextField

+(void)initialize
{
	[self setCellClass:[CenteredTextFieldCell class]];
}

- (id)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
		[self setBezeled:NO];
		[self setEditable:NO];
		[self setSelectable:NO];
		[self setDrawsBackground:NO];
    }
    return self;
}

@end
