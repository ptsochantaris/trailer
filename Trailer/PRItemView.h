//
//  PRItemView.h
//  Trailer
//
//  Created by Paul Tsochantaris on 01/11/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

@class PRItemView;


@protocol PRItemViewDelegate <NSObject>

- (void)unPinSelectedFrom:(PRItemView *)item;
- (void)prItemSelected:(PRItemView *)item;

@end


@interface PRItemView : NSView

@property (nonatomic,weak) id<PRItemViewDelegate> delegate;
@property (nonatomic) BOOL highlighted;
@property (nonatomic) id userInfo;

- (void) setPullRequest:(PullRequest *)pullRequest;

@end
