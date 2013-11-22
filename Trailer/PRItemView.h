//
//  PRItemView.h
//  Trailer
//
//  Created by Paul Tsochantaris on 01/11/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@protocol PRItemViewDelegate <NSObject>

- (void)unPinSelectedFrom:(NSMenuItem *)item;

@end

@interface PRItemView : NSView

@property (nonatomic,weak) id<PRItemViewDelegate> delegate;

- (void) setPullRequest:(PullRequest *)pullRequest;

@end
