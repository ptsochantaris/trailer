#import "PRCell.h"
#import "PullRequest.h"
#import "Settings.h"

static NSNumberFormatter *itemCountFormatter;

@implementation PRCell
{
	UILabel *unreadCount, *readCount;
	NSString *failedToLoadImage, *waitingForImageInPath;
	__weak IBOutlet UIImageView *_image;
	__weak IBOutlet UILabel *_title;
	__weak IBOutlet UILabel *_description;
}

- (void)awakeFromNib
{
	[super awakeFromNib];

	unreadCount = [[UILabel alloc] initWithFrame:CGRectZero];
	unreadCount.textColor = [COLOR_CLASS whiteColor];
	unreadCount.textAlignment = NSTextAlignmentCenter;
	unreadCount.layer.cornerRadius = 8.5;
	unreadCount.clipsToBounds = YES;
	unreadCount.font = [UIFont boldSystemFontOfSize:12.0];
	unreadCount.hidden = YES;
	[self.contentView addSubview:unreadCount];

	readCount = [[UILabel alloc] initWithFrame:CGRectZero];
	readCount.textColor = [COLOR_CLASS darkGrayColor];
	readCount.textAlignment = NSTextAlignmentCenter;
	readCount.layer.cornerRadius = 9.0;
	readCount.clipsToBounds = YES;
	readCount.font = [UIFont systemFontOfSize:12.0];
	readCount.hidden = YES;
	[self.contentView addSubview:readCount];

	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		itemCountFormatter = [[NSNumberFormatter alloc] init];
		itemCountFormatter.numberStyle = NSNumberFormatterDecimalStyle;
	});

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(networkStateChanged)
												 name:kReachabilityChangedNotification
											   object:nil];
}

- (void)networkStateChanged
{
	if(!failedToLoadImage) return;
	if([app.api.reachability currentReachabilityStatus]!=NotReachable)
	{
		[self loadImageAtPath:failedToLoadImage];
	}
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setPullRequest:(PullRequest *)pullRequest
{
	UIFont *detailFont = [UIFont systemFontOfSize:[UIFont smallSystemFontSize]];

	_title.attributedText = [pullRequest titleWithFont:_title.font
											 labelFont:[detailFont fontWithSize:detailFont.pointSize-2.0]
											titleColor:[COLOR_CLASS darkTextColor]];

	_description.attributedText = [pullRequest subtitleWithFont:detailFont
													 lightColor:[COLOR_CLASS lightGrayColor]
													  darkColor:[COLOR_CLASS darkGrayColor]];

	NSInteger _commentsNew=0;
	NSInteger _commentsTotal = pullRequest.totalComments.integerValue;
	if(settings.showCommentsEverywhere || pullRequest.isMine || pullRequest.commentedByMe)
	{
		_commentsNew = pullRequest.unreadComments.integerValue;
	}

	readCount.text = [itemCountFormatter stringFromNumber:@(_commentsTotal)];
	CGSize size = [readCount sizeThatFits:CGSizeMake(200, 14.0)];
	readCount.frame = CGRectMake(0, 0, size.width+10.0, 17.0);
	readCount.hidden = (_commentsTotal==0);

	unreadCount.hidden = _commentsNew==0;
	unreadCount.text = [itemCountFormatter stringFromNumber:@(_commentsNew)];
	size = [unreadCount sizeThatFits:CGSizeMake(200, 18.0)];
	unreadCount.frame = CGRectMake(0, 0, size.width+10.0, 17.0);

	NSString *imagePath = pullRequest.userAvatarUrl;
	if(imagePath)
		[self loadImageAtPath:imagePath];
	else
		failedToLoadImage = nil;

	self.accessibilityLabel = [NSString stringWithFormat:@"%@, %@ unread comments, %@ total comments, %@",
							   [pullRequest accessibleTitle],
							   unreadCount.text,
							   readCount.text,
							   [pullRequest accessibleSubtitle]];

	[self setNeedsLayout];
}

- (void)loadImageAtPath:(NSString *)imagePath
{
	waitingForImageInPath = imagePath;
	if(![app.api haveCachedAvatar:imagePath
			   tryLoadAndCallback:^(id image) {
				   if([waitingForImageInPath isEqualToString:imagePath])
				   {
					   if(image)
					   {
						   // image loaded
						   _image.image = image;
						   failedToLoadImage = nil;
					   }
					   else
					   {
						   // load failed / no image
						   _image.image = [UIImage imageNamed:@"avatarPlaceHolder"];
						   failedToLoadImage = imagePath;
					   }
					   waitingForImageInPath = nil;
				   }
			   }])
	{
		// prepare UI for over-the-network load
		_image.image = [UIImage imageNamed:@"avatarPlaceHolder"];
		failedToLoadImage = nil;
	}
}

- (void)layoutSubviews
{
	[super layoutSubviews];

	CGPoint topLeft = CGPointMake(_image.frame.origin.x, _image.frame.origin.y);
	unreadCount.center = topLeft;
	[self.contentView bringSubviewToFront:unreadCount];

	CGPoint bottomRight = CGPointMake(topLeft.x+_image.frame.size.width, topLeft.y+_image.frame.size.height);
	readCount.center = bottomRight;
	[self.contentView bringSubviewToFront:readCount];
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
	[super setSelected:selected animated:animated];
	[self tone:selected];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated
{
	[super setHighlighted:highlighted animated:animated];
	[self tone:highlighted];
}

- (void)tone:(BOOL)tone
{
	unreadCount.backgroundColor = [COLOR_CLASS redColor];
	readCount.backgroundColor = [COLOR_CLASS colorWithWhite:0.9 alpha:1.0];
}

@end
