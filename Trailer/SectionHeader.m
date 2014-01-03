
@implementation SectionHeader

static NSDictionary *_titleAttributes;
static CGColorRef _lightGray;

+ (void)initialize
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{

		NSMutableParagraphStyle *pCenter = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
		pCenter.alignment = NSCenterTextAlignment;

		_lightGray = CGColorCreateCopy([NSColor colorWithWhite:0.92 alpha:1.0].CGColor);

		_titleAttributes = @{
							 NSFontAttributeName:[NSFont boldSystemFontOfSize:14.0],
							 NSForegroundColorAttributeName:[NSColor lightGrayColor],
							 NSBackgroundColorAttributeName:[NSColor clearColor],
							 };
	});
}

#define TITLE_HEIGHT 42

- (id)initWithRemoveAllDelegate:(id<SectionHeaderDelegate>)delegate title:(NSString *)title
{
    self = [super initWithFrame:CGRectMake(0, 0, MENU_WIDTH, TITLE_HEIGHT)];
    if (self) {
		self.delegate = delegate;
		if(delegate)
		{
			NSButton *_unpin = [[NSButton alloc] initWithFrame:CGRectMake(MENU_WIDTH-100, -4.0, 90, TITLE_HEIGHT)];
			[_unpin setTitle:@"Remove All"];
			[_unpin setTarget:self];
			[_unpin setAction:@selector(unPinSelected:)];
			[_unpin setButtonType:NSMomentaryLightButton];
			[_unpin setBezelStyle:NSRoundRectBezelStyle];
			[_unpin setFont:[NSFont systemFontOfSize:10.0]];
			[self addSubview:_unpin];
		}

		CGRect titleRect = CGRectMake(12, 0, MENU_WIDTH-120-AVATAR_SIZE-LEFTPADDING, TITLE_HEIGHT-8.0);
		CenteredTextField *titleView = [[CenteredTextField alloc] initWithFrame:titleRect];
		titleView.attributedStringValue = [[NSAttributedString alloc] initWithString:title attributes:_titleAttributes];
		[self addSubview:titleView];
    }
    return self;
}

-(void)drawRect:(NSRect)dirtyRect
{
	[super drawRect:dirtyRect];
	CGContextRef context = (CGContextRef) [[NSGraphicsContext currentContext] graphicsPort];
	CGContextSetFillColorWithColor(context, _lightGray);
	CGContextFillRect(context, CGRectMake(1.0, self.bounds.size.height-5.0, MENU_WIDTH-2.0, 1.0));
}

- (void)unPinSelected:(NSButton *)button
{
	[self.delegate sectionHeaderRemoveSelectedFrom:self];
}

@end
