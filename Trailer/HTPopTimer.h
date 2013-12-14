//
//  HTPopTimer.h
//  HouseTrip Host
//
//  Created by Paul Tsochantaris on 09/05/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

@interface HTPopTimer : NSObject

typedef void (^HTBackgroundExpirationHandler)();

@property (nonatomic,readonly) BOOL isRunning;
@property (nonatomic) id userInfo;
@property (nonatomic) NSString *debugName;
@property (nonatomic) NSTimeInterval timeInterval;
@property (nonatomic,copy) HTBackgroundExpirationHandler backgroundExpirationHandler;

- (instancetype)initWithTimeInterval:(NSTimeInterval)popTime target:(id)target selector:(SEL)selector;

- (void)push;

- (void)invalidate;

@end
