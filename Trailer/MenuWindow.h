
@interface MenuWindow : NSWindow

@property (weak) IBOutlet MenuScrollView *scrollView;

- (void)layout;

@end
