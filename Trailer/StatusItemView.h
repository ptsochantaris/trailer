
@class StatusItemView;


#define STATUSITEM_PADDING 1.0
#define DARK_MODE_CHANGED @"DarkModeChangedNotificationKey"

@protocol StatusItemDelegate <NSObject>
- (void)statusItemTapped:(StatusItemView *)statusItem;
@end


@interface StatusItemView : NSView

- (id)initWithFrame:(NSRect)frame
			  label:(NSString *)label
		 attributes:(NSDictionary *)attributes
		   delegate:(id<StatusItemDelegate>)delegate;

@property (nonatomic) BOOL highlighted, grayOut, darkMode;

@end
