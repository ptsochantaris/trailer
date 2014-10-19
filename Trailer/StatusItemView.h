
@class StatusItemView;


#define STATUSITEM_PADDING 1.0


@protocol StatusItemDelegate <NSObject>

- (void)statusItemTapped:(StatusItemView *)statusItem;

@end


@interface StatusItemView : NSView

- (id)initWithFrame:(NSRect)frame
			  label:(NSString *)label
		 attributes:(NSDictionary *)attributes
		   delegate:(id<StatusItemDelegate>)delegate;

@property (nonatomic) BOOL highlighted, grayOut;

@end
