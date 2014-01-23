
@interface PRItemView ()
{
	BOOL _highlighted;
	NSTrackingArea *trackingArea;
}
@end

static NSDictionary *_titleAttributes, *_createdAttributes;
static NSDateFormatter *dateFormatter;
static CGColorRef _highlightColor;

@implementation PRItemView

#define REMOVE_BUTTON_WIDTH 80.0
#define DATE_PADDING 16.0
#define CELL_PADDING 4.0

+ (void)initialize
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{

		dateFormatter = [[NSDateFormatter alloc] init];
		dateFormatter.dateStyle = NSDateFormatterLongStyle;
		dateFormatter.timeStyle = NSDateFormatterMediumStyle;
		dateFormatter.doesRelativeDateFormatting = YES;

		_highlightColor = CGColorCreateCopy([NSColor colorWithWhite:0.95 alpha:1.0].CGColor);

		_titleAttributes = @{
							 NSFontAttributeName:[NSFont menuFontOfSize:13.0],
							 NSForegroundColorAttributeName:[NSColor blackColor],
							 NSBackgroundColorAttributeName:[NSColor clearColor],
							 };
		_createdAttributes = @{
							   NSFontAttributeName:[NSFont menuFontOfSize:10.0],
							   NSForegroundColorAttributeName:[NSColor grayColor],
							   NSBackgroundColorAttributeName:[NSColor clearColor],
							   };
	});
}

#define AVATAR_PADDING 8.0

- (instancetype)initWithPullRequest:(PullRequest *)pullRequest userInfo:(id)userInfo delegate:(id<PRItemViewDelegate>)delegate
{
    self = [super init];
    if (self)
	{
		_delegate = delegate;
		_userInfo = userInfo;

		NSInteger _commentsNew=0;
		NSInteger _commentsTotal = pullRequest.totalComments.integerValue;
		if([Settings shared].showCommentsEverywhere || pullRequest.isMine || pullRequest.commentedByMe)
		{
			_commentsNew = pullRequest.unreadComments.integerValue;
		}

		NSString *_dates, *_title;
		if([Settings shared].showCreatedInsteadOfUpdated)
		{
			_dates = [dateFormatter stringFromDate:pullRequest.createdAt];
		}
		else
		{
			_dates = [dateFormatter stringFromDate:pullRequest.updatedAt];
		}

		if(pullRequest.userLogin.length)
		{
			_dates = [NSString stringWithFormat:@"%@ - %@",pullRequest.userLogin,_dates];
		}

		_title = pullRequest.title;
		if(!_title) _title = @"(No title)";

		CGFloat W = MENU_WIDTH-LEFTPADDING;
		BOOL showUnpin = pullRequest.condition.integerValue!=kPullRequestConditionOpen;
		if(showUnpin) W -= REMOVE_BUTTON_WIDTH;

		BOOL showAvatar = pullRequest.userAvatarUrl.length && ![Settings shared].hideAvatars;
		if(showAvatar) W -= (AVATAR_SIZE+AVATAR_PADDING);
		else W += 4.0;

		CGRect titleSize = [_title boundingRectWithSize:CGSizeMake(W, FLT_MAX)
												options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading
											 attributes:_titleAttributes];
		CGFloat H = titleSize.size.height;
		self.frame = CGRectMake(0, 0, MENU_WIDTH, H+DATE_PADDING+CELL_PADDING);
		CGRect titleRect = CGRectMake(LEFTPADDING, DATE_PADDING+CELL_PADDING*0.5, W, H);
		CGRect dateRect = CGRectMake(LEFTPADDING, CELL_PADDING*0.5, W, DATE_PADDING);
		CGRect pinRect = CGRectMake(LEFTPADDING+W, floorf((self.bounds.size.height-24.0)*0.5), REMOVE_BUTTON_WIDTH-10.0, 24.0);

		if(showAvatar)
		{
			RemoteImageView *userImage = [[RemoteImageView alloc] initWithFrame:CGRectMake(LEFTPADDING, (self.bounds.size.height-AVATAR_SIZE)*0.5, AVATAR_SIZE, AVATAR_SIZE) url:pullRequest.userAvatarUrl];
			[self addSubview:userImage];

			CGFloat shift = AVATAR_PADDING+AVATAR_SIZE;
			pinRect = CGRectOffset(pinRect, shift, 0);
			dateRect = CGRectOffset(dateRect, shift, 0);
			titleRect = CGRectOffset(titleRect, shift, 0);
		}
		else
		{
			CGFloat shift = -4.0;
			pinRect = CGRectOffset(pinRect, shift, 0);
			dateRect = CGRectOffset(dateRect, shift, 0);
			titleRect = CGRectOffset(titleRect, shift, 0);
		}

		if(showUnpin)
		{
			NSButton *unpin = [[NSButton alloc] initWithFrame:pinRect];
			[unpin setTitle:@"Remove"];
			[unpin setTarget:self];
			[unpin setAction:@selector(unPinSelected:)];
			[unpin setButtonType:NSMomentaryLightButton];
			[unpin setBezelStyle:NSRoundRectBezelStyle];
			[unpin setFont:[NSFont systemFontOfSize:10.0]];
			[self addSubview:unpin];
		}

		CenteredTextField *title = [[CenteredTextField alloc] initWithFrame:titleRect];
		title.attributedStringValue = [[NSAttributedString alloc] initWithString:_title attributes:_titleAttributes];
		[self addSubview:title];

		CenteredTextField *subtitle = [[CenteredTextField alloc] initWithFrame:dateRect];
		subtitle.attributedStringValue = [[NSAttributedString alloc] initWithString:_dates attributes:_createdAttributes];
		[self addSubview:subtitle];

		CommentCounts *commentCounts = [[CommentCounts alloc] initWithFrame:CGRectMake(0, 0, LEFTPADDING, self.bounds.size.height)
																unreadCount:_commentsNew
																 totalCount:_commentsTotal];
		[self addSubview:commentCounts];
    }
    return self;
}

- (void)unPinSelected:(NSButton *)button
{
	[self.delegate unPinSelectedFrom:self];
}

- (void)drawRect:(NSRect)dirtyRect
{
	[super drawRect:dirtyRect];
	if(_highlighted)
	{
		CGContextRef context = (CGContextRef) [[NSGraphicsContext currentContext] graphicsPort];
		CGContextSetFillColorWithColor(context, _highlightColor);
		CGContextFillRect(context, CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height));
	}
}

- (void)mouseEntered:(NSEvent *)theEvent
{
	_highlighted = YES;
	[self setNeedsDisplay:YES];
}

- (void)mouseExited:(NSEvent *)theEvent
{
	_highlighted = NO;
	[self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent*) event
{
	[self.delegate prItemSelected:self];
}

- (void)updateTrackingAreas
{
	if(trackingArea) [self removeTrackingArea:trackingArea];
	trackingArea = [ [NSTrackingArea alloc] initWithRect:[self bounds]
												 options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow
												   owner:self
												userInfo:nil];
	[self addTrackingArea:trackingArea];

	NSPoint mouseLocation = [[self window] mouseLocationOutsideOfEventStream];
    mouseLocation = [self convertPoint: mouseLocation fromView: nil];

    if (NSPointInRect(mouseLocation, [self bounds]))
		[self mouseEntered: nil];
	else
		[self mouseExited: nil];
}

@end
