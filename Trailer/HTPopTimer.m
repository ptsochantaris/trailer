
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
    }
    return self;
}

- (BOOL)isRunning
{
    return (popTimer!=nil);
}

- (void)push
{
    if(popTimer) [popTimer invalidate];
    popTimer = [NSTimer scheduledTimerWithTimeInterval:_timeInterval target:self selector:@selector(popped) userInfo:nil repeats:NO];
}

- (void)invalidate
{
    [popTimer invalidate];
    popTimer = nil;
}

- (void)popped
{
    [self invalidate];

	NSMethodSignature *methodSig = [[_target class] instanceMethodSignatureForSelector:_selector];
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:methodSig];
	[invocation setSelector:_selector];
	[invocation setTarget:_target];
	[invocation invoke];
}

@end
