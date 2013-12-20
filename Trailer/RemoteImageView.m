//
//  RemoteImageView.m
//  Trailer
//
//  Created by Paul Tsochantaris on 20/12/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

@interface RemoteImageView ()
{
}
@end

@implementation RemoteImageView

- (id)initWithFrame:(NSRect)frameRect url:(NSString *)urlPath
{
	self = [self initWithFrame:frameRect];
	if(self)
	{
		self.imageAlignment = NSImageAlignCenter;
		self.imageScaling = NSImageScaleProportionallyUpOrDown;
		[[AppDelegate shared].api getImage:urlPath
								   success:^(NSHTTPURLResponse *response, NSImage *image) {
									   self.image = image;
								   } failure:^(NSHTTPURLResponse *response, NSError *error) {
								   }];
	}
	return self;
}

@end
