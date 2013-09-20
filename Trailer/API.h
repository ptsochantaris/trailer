//
//  API.h
//  Trailer
//
//  Created by Paul Tsochantaris on 20/09/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

#import <Foundation/Foundation.h>

#define GITHUB_TOKEN_KEY @"GITHUB_AUTH_TOKEN"

@interface API : NSObject

@property (nonatomic,readonly) NSString *authToken;

-(void)fetchRepositoriesAndCallback:(void(^)(BOOL success))callback;

@end
