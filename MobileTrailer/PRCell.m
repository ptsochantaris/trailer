
@interface PRCell ()
{
	UILabel *unreadCount, *readCount;
    NSString *failedToLoadImage, *waitingForImageInPath;
}
@end

static NSNumberFormatter *itemCountFormatter;

@implementation PRCell

- (void)awakeFromNib
{
	[super awakeFromNib];
	self.textLabel.numberOfLines = 0;
	self.detailTextLabel.textColor = [COLOR_CLASS grayColor];

	unreadCount = [[UILabel alloc] initWithFrame:CGRectZero];
	unreadCount.textColor = [COLOR_CLASS whiteColor];
	unreadCount.textAlignment = NSTextAlignmentCenter;
	unreadCount.layer.cornerRadius = 9.0;
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
    if([[AppDelegate shared].api.reachability currentReachabilityStatus]!=NotReachable)
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
	self.textLabel.text = pullRequest.title;
	self.detailTextLabel.text = pullRequest.subtitle;

	NSInteger _commentsNew=0;
	NSInteger _commentsTotal = pullRequest.totalComments.integerValue;
	if([Settings shared].showCommentsEverywhere || pullRequest.isMine || pullRequest.commentedByMe)
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

	[self setNeedsLayout];
}

- (void)loadImageAtPath:(NSString *)imagePath
{
	waitingForImageInPath = imagePath;
    if(![[AppDelegate shared].api haveCachedAvatar:imagePath
								tryLoadAndCallback:^(id image) {
									if([waitingForImageInPath isEqualToString:imagePath])
									{
										if(image)
										{
											// image loaded
											self.imageView.image = image;
											failedToLoadImage = nil;
										}
										else
										{
											// load failed / no image
											self.imageView.image = [UIImage imageNamed:@"avatarPlaceHolder"];
											failedToLoadImage = imagePath;
										}
										waitingForImageInPath = nil;
									}
								}])
    {
		// prepare UI for over-the-network load
        self.imageView.image = [UIImage imageNamed:@"avatarPlaceHolder"];
        failedToLoadImage = nil;
    }
}

- (void)layoutSubviews
{
	[super layoutSubviews];

	self.imageView.contentMode = UIViewContentModeCenter;
	self.imageView.clipsToBounds = YES;

	CGPoint topLeft = CGPointMake(self.imageView.frame.origin.x, self.imageView.frame.origin.y);
	unreadCount.center = topLeft;
	[self.contentView bringSubviewToFront:unreadCount];

	CGPoint bottomRight = CGPointMake(topLeft.x+self.imageView.frame.size.width, topLeft.y+self.imageView.frame.size.height);
	readCount.center = bottomRight;
	[self.contentView bringSubviewToFront:readCount];
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
	[super setSelected:selected animated:animated];

	unreadCount.backgroundColor = [COLOR_CLASS redColor];
	readCount.backgroundColor = [COLOR_CLASS colorWithWhite:0.9 alpha:1.0];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated
{
    [super setHighlighted:highlighted animated:animated];

	unreadCount.backgroundColor = [COLOR_CLASS redColor];
	readCount.backgroundColor = [COLOR_CLASS colorWithWhite:0.9 alpha:1.0];
}

@end
