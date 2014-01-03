
@interface HTPopTimer : NSObject

typedef void (^HTBackgroundExpirationHandler)();

@property (nonatomic,readonly) BOOL isRunning;
@property (nonatomic) id userInfo;
@property (nonatomic) NSTimeInterval timeInterval;
@property (nonatomic,copy) HTBackgroundExpirationHandler backgroundExpirationHandler;

- (instancetype)initWithTimeInterval:(NSTimeInterval)popTime target:(id)target selector:(SEL)selector;

- (void)push;

- (void)invalidate;

@end
