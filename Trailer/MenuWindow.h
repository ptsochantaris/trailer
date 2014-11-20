
#define TOP_HEADER_HEIGHT 28.0

@interface MenuWindow : NSWindow

@property (weak) IBOutlet MenuScrollView *scrollView;
@property (weak) IBOutlet NSViewAllowsVibrancy *header;

- (void)scrollToView:(NSView *)view;

+ (BOOL)usingVibrancy;

- (void)updateVibrancy;

@end
