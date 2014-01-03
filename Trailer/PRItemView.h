
#define AVATAR_SIZE 26.0
#define LEFTPADDING 44.0

@class PRItemView;


@protocol PRItemViewDelegate <NSObject>

- (void)unPinSelectedFrom:(PRItemView *)item;
- (void)prItemSelected:(PRItemView *)item;

@end


@interface PRItemView : NSView

@property (nonatomic,weak) id<PRItemViewDelegate> delegate;
@property (nonatomic) id userInfo;

- (instancetype)initWithPullRequest:(PullRequest *)pullRequest userInfo:(id)userInfo delegate:(id<PRItemViewDelegate>)delegate;

@end
