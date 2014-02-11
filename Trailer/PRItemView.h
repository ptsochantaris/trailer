
#define AVATAR_SIZE 26.0
#define LEFTPADDING 44.0

#define PR_ITEM_FOCUSED_NOTIFICATION_KEY @"PrItemFocusedNotificationKey"
#define PR_ITEM_FOCUSED_STATE_KEY @"PrItemFocusedStateKey"


@class PRItemView;


@protocol PRItemViewDelegate <NSObject>

- (void)unPinSelectedFrom:(PRItemView *)item;
- (void)prItemSelected:(PRItemView *)item alternativeSelect:(BOOL)isAlternative;

@end


@interface PRItemView : NSView

@property (nonatomic,weak) id<PRItemViewDelegate> delegate;
@property (nonatomic) id userInfo;
@property (nonatomic) BOOL focused;

- (instancetype)initWithPullRequest:(PullRequest *)pullRequest userInfo:(id)userInfo delegate:(id<PRItemViewDelegate>)delegate;

@end
