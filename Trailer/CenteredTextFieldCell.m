
@implementation CenteredTextFieldCell

- (NSRect)drawingRectForBounds:(NSRect)theRect
{
    NSRect newRect = [super drawingRectForBounds:theRect];
	NSSize textSize = [self cellSizeForBounds:theRect];
	float heightDelta = newRect.size.height - textSize.height;
	if (heightDelta > 0)
	{
		newRect.size.height -= heightDelta;
		newRect.origin.y += floorf(heightDelta * 0.5);
	}
    return newRect;
}

@end
