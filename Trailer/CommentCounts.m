#import "CommentCounts.h"

static NSDictionary *_commentAlertAttributes;
static NSNumberFormatter *formatter;
static COLOR_CLASS *_redFill;
static NSMutableParagraphStyle *pCenter;

@implementation CommentCounts

+ (void)initialize
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		formatter = [[NSNumberFormatter alloc] init];
		formatter.numberStyle = NSNumberFormatterDecimalStyle;

		pCenter = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
		pCenter.alignment = NSCenterTextAlignment;

		_commentAlertAttributes = @{ NSFontAttributeName:[NSFont menuFontOfSize:8.0],
									 NSForegroundColorAttributeName:[NSColor whiteColor],
									 NSParagraphStyleAttributeName:pCenter,
									 };
		_redFill = MAKECOLOR(1.0, 0.4, 0.4, 1.0);
	});
}

- (id)initWithFrame:(NSRect)frame unreadCount:(NSInteger)unreadCount totalCount:(NSInteger)totalCount
{
	self = [super initWithFrame:frame];
	if (self)
	{
		self.canDrawSubviewsIntoLayer = YES;

		if(totalCount)
		{
			unreadCount = 888;
			BOOL darkMode = ((StatusItemView *)app.statusItem.view).darkMode;
			NSDictionary *a = @{ NSFontAttributeName:[NSFont menuFontOfSize:11.0],
								 NSForegroundColorAttributeName:darkMode ? [COLOR_CLASS controlLightHighlightColor] : [COLOR_CLASS controlTextColor],
								 NSParagraphStyleAttributeName:pCenter,
								 };

			NSAttributedString *countString = [[NSAttributedString alloc] initWithString:[formatter stringFromNumber:@(totalCount)] attributes:a];

			CGFloat width = MAX(BASE_BADGE_SIZE,[countString size].width+10.0);
			CGFloat height = BASE_BADGE_SIZE;
			CGFloat bottom = (self.bounds.size.height-height)*0.5;
			CGFloat left = (self.bounds.size.width-width)*0.5;

			CenterTextField *countView = [[CenterTextField alloc] initWithFrame:NSIntegralRect(NSMakeRect(left, bottom, width, height))];
			countView.attributedStringValue = countString;
			countView.wantsLayer = YES;
			countView.layer.cornerRadius = 4.0;
			CGColorRef color = [MenuWindow usingVibrancy] ? [COLOR_CLASS controlLightHighlightColor].CGColor : MAKECOLOR(0.94, 0.94, 0.94, 1.0).CGColor;

			StatusItemView *v = (StatusItemView*)app.statusItem.view;
			if([MenuWindow usingVibrancy] && v.darkMode)
			{
				((CenterTextFieldCell*)countView.cell).verticalTweak = 0;
				countView.layer.borderColor = color;
				countView.layer.borderWidth = 0.5;
			}
			else
			{
				countView.layer.backgroundColor = color;
				countView.drawsBackground = YES;
				if([MenuWindow usingVibrancy])
				{
					((CenterTextFieldCell*)countView.cell).verticalTweak = 4;
				}
				else
				{
					((CenterTextFieldCell*)countView.cell).drawsBackground = false;
				}
			}
			[self addSubview:countView positioned:NSWindowAbove relativeTo:nil];

			if(unreadCount)
			{
				bottom += height;
				countString = [[NSAttributedString alloc] initWithString:[formatter stringFromNumber:@(unreadCount)] attributes:_commentAlertAttributes];
				width = MAX(SMALL_BADGE_SIZE,[countString size].width+8.0);
				height = SMALL_BADGE_SIZE;
				left -= width * 0.5;
				bottom -= (height * 0.5)+1.0;

				countView = [[CenterTextField alloc] initWithFrame:NSIntegralRect(NSMakeRect(left, bottom, width, height))];
				((CenterTextFieldCell*)countView.cell).verticalTweak = 1.0;
				countView.attributedStringValue = countString;
				countView.wantsLayer = YES;
				countView.backgroundColor = _redFill;
				countView.drawsBackground = YES;
				countView.layer.cornerRadius = floorf(SMALL_BADGE_SIZE*0.5);
				[self addSubview:countView positioned:NSWindowBelow relativeTo:nil];
			}
		}
	}
	return self;
}

@end
