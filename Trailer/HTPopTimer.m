//
//  HTPopTimer.m
//
//  Created by Paul Tsochantaris on 09/05/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

@interface HTPopTimer ()
{
    NSTimer *popTimer;
    id _target;
    SEL _selector;
}
@end

@implementation HTPopTimer

- (instancetype)initWithTimeInterval:(NSTimeInterval)popTime target:(id)target selector:(SEL)selector
{
    self = [self init];
    if(self)
    {
        _target = target;
        _selector = selector;
        _timeInterval = popTime;
		_debugName = @"Pop timer";
    }
    return self;
}

- (BOOL)isRunning
{
    return (popTimer!=nil);
}

- (void)push
{
    NSLog(@"%@ pushed",self.debugName);
    if(popTimer) [popTimer invalidate];
    popTimer = [NSTimer scheduledTimerWithTimeInterval:_timeInterval target:self selector:@selector(popped) userInfo:nil repeats:NO];
}

- (void)invalidate
{
    NSLog(@"%@ invalidated",self.debugName);
    [popTimer invalidate];
    popTimer = nil;
}

- (void)popped
{
    NSLog(@"%@ popped",self.debugName);
    [self invalidate];

	NSMethodSignature *methodSig = [[_target class] instanceMethodSignatureForSelector:_selector];
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSig];
	[invocation setSelector:_selector];
	[invocation setTarget:_target];
	[invocation invoke];
}

@end
