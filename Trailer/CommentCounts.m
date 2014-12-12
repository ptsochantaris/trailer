#import "CommentCounts.h"

static NSDictionary *_commentAlertAttributes;
static NSNumberFormatter *formatter;
static CGColorRef _redFill;
static NSMutableParagraphStyle *pCenter;

@interface CommentCounts ()
{
	NSInteger _unreadCount, _totalCount;
}
@end

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
		_redFill = CGColorCreateCopy(MAKECOLOR(1.0, 0.4, 0.4, 1.0).CGColor);
	});
}

- (id)initWithFrame:(NSRect)frame unreadCount:(NSInteger)unreadCount totalCount:(NSInteger)totalCount
{
	self = [super initWithFrame:frame];
	if (self) {
		_unreadCount = unreadCount;
		_totalCount = totalCount;
	}
	return self;
}

typedef NS_ENUM(NSInteger, RoundedCorners) {
	kRoundedCornerNone = 0,
	kRoundedCornerTopLeft = 1,
	kRoundedCornerTopRight = 2,
	kRoundedCornerBottomLeft = 4,
	kRoundedCornerBottomRight = 8
};

#define BASE_BADGE_SIZE 21.0
#define SMALL_BADGE_SIZE 14.0

- (void)drawRect:(NSRect)dirtyRect
{
	[super drawRect:dirtyRect];

	if(_totalCount)
	{
		CGContextRef context = (CGContextRef) [[NSGraphicsContext currentContext] graphicsPort];

		NSString *countString = [formatter stringFromNumber:@(_totalCount)];

		NSDictionary *_commentCountAttributes = @{ NSFontAttributeName:[NSFont menuFontOfSize:11.0],
												   NSForegroundColorAttributeName:[NSColor controlTextColor],
												   NSParagraphStyleAttributeName:pCenter,
												   };

		CGFloat width = MAX(BASE_BADGE_SIZE,[countString sizeWithAttributes:_commentCountAttributes].width+10.0);
		CGFloat height = BASE_BADGE_SIZE;
		CGFloat bottom = (self.bounds.size.height-height)*0.5;
		CGFloat left = (self.bounds.size.width-width)*0.5;

		CGRect countRect = CGRectMake(left, bottom, width, height);
		StatusItemView *v = (StatusItemView*)app.statusItem.view;
		[self drawRoundRect:countRect
				  withColor:[MenuWindow usingVibrancy] ? [COLOR_CLASS controlLightHighlightColor].CGColor : MAKECOLOR(0.94, 0.94, 0.94, 1.0).CGColor
					corners:kRoundedCornerTopLeft|kRoundedCornerBottomLeft|kRoundedCornerBottomRight|kRoundedCornerTopRight
					 radius:4.0
					   fill:!([MenuWindow usingVibrancy] && v.darkMode)
				  inContext:context];

		countRect = CGRectOffset(countRect, 0, -3.0);
		[countString drawInRect:countRect withAttributes:_commentCountAttributes];

		if(_unreadCount)
		{
			bottom += height;
			//left += width;

			countString = [formatter stringFromNumber:@(_unreadCount)];
			width = MAX(SMALL_BADGE_SIZE,[countString sizeWithAttributes:_commentAlertAttributes].width+6.0);;
			height = SMALL_BADGE_SIZE;

			left -= width * 0.5;
			bottom -= (height * 0.5)+1.0;

			CGRect countRect = CGRectMake(left, bottom, width, height);
			[self drawRoundRect:countRect
					  withColor:_redFill
						corners:kRoundedCornerTopLeft|kRoundedCornerBottomLeft|kRoundedCornerBottomRight|kRoundedCornerTopRight
						 radius:SMALL_BADGE_SIZE*0.5
						   fill:YES
					  inContext:context];

			countRect = CGRectOffset(countRect, 0, -1.0);
			[countString drawInRect:countRect withAttributes:_commentAlertAttributes];
		}
	}
}

- (void)drawRoundRect:(CGRect)rect
			withColor:(CGColorRef)color
			  corners:(RoundedCorners)corners
			   radius:(CGFloat)radius
				 fill:(BOOL)fill
			inContext:(CGContextRef)context
{
	CGRect innerRect = CGRectInset(rect, radius, radius);

	CGFloat inside_right = innerRect.origin.x + innerRect.size.width;
	CGFloat outside_right = rect.origin.x + rect.size.width;
	CGFloat inside_bottom = innerRect.origin.y + innerRect.size.height;
	CGFloat outside_bottom = rect.origin.y + rect.size.height;

	CGFloat inside_left = innerRect.origin.x;
	CGFloat inside_top = innerRect.origin.y;
	CGFloat outside_top = rect.origin.y;
	CGFloat outside_left = rect.origin.x;

	CGContextBeginPath(context);

	if(corners & kRoundedCornerTopLeft)
	{
		CGContextMoveToPoint(context, innerRect.origin.x, outside_top);
	}
	else
	{
		CGContextMoveToPoint(context, outside_left, outside_top);
	}

	if(corners & kRoundedCornerTopRight)
	{
		CGContextAddLineToPoint(context, inside_right, outside_top);
		CGContextAddArcToPoint(context, outside_right, outside_top, outside_right, inside_top, radius);
	}
	else
	{
		CGContextAddLineToPoint(context, outside_right, outside_top);
	}

	if(corners & kRoundedCornerBottomRight)
	{
		CGContextAddLineToPoint(context, outside_right, inside_bottom);
		CGContextAddArcToPoint(context,  outside_right, outside_bottom, inside_right, outside_bottom, radius);
	}
	else
	{
		CGContextAddLineToPoint(context, outside_right, outside_bottom);
	}

	if(corners & kRoundedCornerBottomLeft)
	{
		CGContextAddLineToPoint(context, inside_left, outside_bottom);
		CGContextAddArcToPoint(context,  outside_left, outside_bottom, outside_left, inside_bottom, radius);
	}
	else
	{
		CGContextAddLineToPoint(context, outside_left, outside_bottom);
	}

	if(corners & kRoundedCornerTopLeft)
	{
		CGContextAddLineToPoint(context, outside_left, inside_top);
		CGContextAddArcToPoint(context,  outside_left, outside_top, innerRect.origin.x, outside_top, radius);
	}
	else
	{
		CGContextAddLineToPoint(context, outside_left, outside_top);
	}

	if(fill)
	{
		CGContextSetFillColorWithColor(context, color);
		CGContextFillPath(context);
	}
	else
	{
		CGContextSetLineWidth(context, 0.5);
		CGContextSetStrokeColorWithColor(context, color);
		CGContextStrokePath(context);
	}
}

@end
