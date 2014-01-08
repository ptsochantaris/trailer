//
//  NSImage+Scale.h
//  Trailer
//
//  Created by Paul Tsochantaris on 08/01/2014.
//  Copyright (c) 2014 HouseTrip. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface NSImage (Scale)

- (NSImage *)scaleToFillSize:(CGSize)toSize;

@end
