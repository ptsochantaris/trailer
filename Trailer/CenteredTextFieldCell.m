//
//  CenteredTextField.m
//  Trailer
//
//  Created by Paul Tsochantaris on 22/12/13.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

@implementation CenteredTextFieldCell

- (NSRect)drawingRectForBounds:(NSRect)theRect
{
    NSRect newRect = [super drawingRectForBounds:theRect];
	NSSize textSize = [self cellSizeForBounds:theRect];
	float heightDelta = newRect.size.height - textSize.height;
	if (heightDelta > 0)
	{
		newRect.size.height -= heightDelta;
		newRect.origin.y += (heightDelta * 0.5);
	}
    return newRect;
}

@end
