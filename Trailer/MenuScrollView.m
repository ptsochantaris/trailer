
@implementation MenuScrollView

- (void)scrollWheel:(NSEvent *)theEvent
{
	if(!_ignoreWheel)
	{
		[super scrollWheel:theEvent];
	}
}

@end
