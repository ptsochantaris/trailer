
#define TOP_HEADER_HEIGHT 28.0

@class ViewAllowsVibrancy;

@interface MenuWindow : NSWindow

@property (weak) IBOutlet NSScrollView *scrollView;
@property (weak) IBOutlet ViewAllowsVibrancy *header;

- (void)scrollToView:(NSView *)view;

+ (BOOL)usingVibrancy;

- (void)updateVibrancy;

@end
