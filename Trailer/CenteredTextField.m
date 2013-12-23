//
//  CenteredTextField.m
//  Trailer
//
//  Created by Paul Tsochantaris on 22/12/13.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

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
