
@interface MenuWindow : NSWindow

@property (weak) IBOutlet MenuScrollView *scrollView;

- (void)layout;

- (void)scrollToView:(NSView *)view;

@end
