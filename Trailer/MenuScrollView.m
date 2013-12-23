//
//  PRScrollView.m
//  Trailer
//
//  Created by Paul Tsochantaris on 14/12/13.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

@implementation MenuScrollView

- (void)scrollWheel:(NSEvent *)theEvent
{
	if(!_ignoreWheel)
	{
		[super scrollWheel:theEvent];
	}
}

@end
