// with many thanks to https://github.com/davbeck/TUSafariActivity for the example and the icon

@implementation OpenInSafariActivity
{
	NSURL *_URL;
}

- (NSString *)activityType
{
	return NSStringFromClass([self class]);
}

- (NSString *)activityTitle
{
	return @"Open in Safari";
}

- (UIImage *)activityImage
{
	return [UIImage imageNamed:@"safariShare"];
}

- (BOOL)canPerformWithActivityItems:(NSArray *)activityItems
{
	for (id activityItem in activityItems)
	{
		if ([activityItem isKindOfClass:[NSURL class]] && [[UIApplication sharedApplication] canOpenURL:activityItem])
		{
			return YES;
		}
	}
	return NO;
}

- (void)prepareWithActivityItems:(NSArray *)activityItems
{
	for (id activityItem in activityItems)
	{
		if ([activityItem isKindOfClass:[NSURL class]])
		{
			_URL = activityItem;
		}
	}
}

- (void)performActivity
{
	[self activityDidFinish:[[UIApplication sharedApplication] openURL:_URL]];
}

@end
