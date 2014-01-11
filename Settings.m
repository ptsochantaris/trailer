//
//  Settings.m
//  Trailer
//
//  Created by Paul Tsochantaris on 11/1/14.
//  Copyright (c) 2014 HouseTrip. All rights reserved.
//

@implementation Settings

+ (Settings *)shared
{
	static Settings *sharedRef;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sharedRef = [[Settings alloc] init];
	});
	return sharedRef;
}

- (NSString *)sortField
{
	switch (self.sortMethod)
	{
		case kCreationDate: return @"createdAt";
		case kRecentActivity: return @"updatedAt";
		case kTitle: return @"title";
	}
	return nil;
}

-(void)storeDefaultValue:(id)value forKey:(NSString *)key
{
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	if(value)
		[d setObject:value forKey:key];
	else
		[d removeObjectForKey:key];
	[d synchronize];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define IOS_BACKGROUND_REFRESH_PERIOD_KEY @"IOS_BACKGROUND_REFRESH_PERIOD_KEY"
-(float)backgroundRefreshPeriod
{
	float period = [[NSUserDefaults standardUserDefaults] floatForKey:IOS_BACKGROUND_REFRESH_PERIOD_KEY];
	if(period==0)
	{
		period = 600.0;
		self.backgroundRefreshPeriod = period;
	}
	return period;
}
-(void)setBackgroundRefreshPeriod:(float)backgroundRefreshPeriod
{
#ifdef __IPHONE_OS_VERSION_MIN_REQUIRED
	[[UIApplication sharedApplication] setMinimumBackgroundFetchInterval:backgroundRefreshPeriod];
#endif
	[[NSUserDefaults standardUserDefaults] setFloat:backgroundRefreshPeriod forKey:IOS_BACKGROUND_REFRESH_PERIOD_KEY];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define REFRESH_PERIOD_KEY @"REFRESH_PERIOD_KEY"
-(float)refreshPeriod
{
	float period = [[NSUserDefaults standardUserDefaults] floatForKey:REFRESH_PERIOD_KEY];
	if(period==0)
	{
		period = 60.0;
		self.refreshPeriod = period;
	}
	return period;
}
-(void)setRefreshPeriod:(float)refreshPeriod { [[NSUserDefaults standardUserDefaults] setFloat:refreshPeriod forKey:REFRESH_PERIOD_KEY]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define GITHUB_TOKEN_KEY @"GITHUB_AUTH_TOKEN"
-(NSString*)authToken { return [[NSUserDefaults standardUserDefaults] stringForKey:GITHUB_TOKEN_KEY]; }
-(void)setAuthToken:(NSString *)authToken
{
	[self storeDefaultValue:authToken forKey:GITHUB_TOKEN_KEY];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define USER_NAME_KEY @"USER_NAME_KEY"
-(NSString *)localUser { return [[NSUserDefaults standardUserDefaults] stringForKey:USER_NAME_KEY]; }
-(void)setLocalUser:(NSString *)localUser { [self storeDefaultValue:localUser forKey:USER_NAME_KEY]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define USER_ID_KEY @"USER_ID_KEY"
-(NSString *)localUserId { return [[NSUserDefaults standardUserDefaults] stringForKey:USER_ID_KEY]; }
-(void)setLocalUserId:(NSString *)localUserId { [self storeDefaultValue:localUserId forKey:USER_ID_KEY]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define HIDE_PRS_KEY @"HIDE_UNCOMMENTED_PRS_KEY"
-(void)setShouldHideUncommentedRequests:(BOOL)shouldHideUncommentedRequests { [self storeDefaultValue:@(shouldHideUncommentedRequests) forKey:HIDE_PRS_KEY]; }
-(BOOL)shouldHideUncommentedRequests { return [[[NSUserDefaults standardUserDefaults] stringForKey:HIDE_PRS_KEY] boolValue]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define SHOW_COMMENTS_EVERYWHERE_KEY @"SHOW_COMMENTS_EVERYWHERE_KEY"
-(BOOL)showCommentsEverywhere { return [[[NSUserDefaults standardUserDefaults] stringForKey:SHOW_COMMENTS_EVERYWHERE_KEY] boolValue]; }
-(void)setShowCommentsEverywhere:(BOOL)showCommentsEverywhere { [self storeDefaultValue:@(showCommentsEverywhere) forKey:SHOW_COMMENTS_EVERYWHERE_KEY]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define SORT_ORDER_KEY @"SORT_ORDER_KEY"
-(BOOL)sortDescending { return [[[NSUserDefaults standardUserDefaults] stringForKey:SORT_ORDER_KEY] boolValue]; }
-(void)setSortDescending:(BOOL)sortDescending { [self storeDefaultValue:@(sortDescending) forKey:SORT_ORDER_KEY]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define SHOW_UPDATED_KEY @"SHOW_UPDATED_KEY"
-(BOOL)showCreatedInsteadOfUpdated { return [[[NSUserDefaults standardUserDefaults] stringForKey:SHOW_UPDATED_KEY] boolValue]; }
-(void)setShowCreatedInsteadOfUpdated:(BOOL)showCreatedInsteadOfUpdated { [self storeDefaultValue:@(showCreatedInsteadOfUpdated) forKey:SHOW_UPDATED_KEY]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define SORT_METHOD_KEY @"SORT_METHOD_KEY"
-(NSInteger)sortMethod { return [[[NSUserDefaults standardUserDefaults] objectForKey:SORT_METHOD_KEY] integerValue]; }
-(void)setSortMethod:(NSInteger)sortMethod { [self storeDefaultValue:@(sortMethod) forKey:SORT_METHOD_KEY]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define DONT_KEEP_MY_PRS_KEY @"DONT_KEEP_MY_PRS_KEY"
-(void)setDontKeepMyPrs:(BOOL)dontKeepMyPrs { [self storeDefaultValue:@(dontKeepMyPrs) forKey:DONT_KEEP_MY_PRS_KEY]; }
-(BOOL)dontKeepMyPrs { return [[[NSUserDefaults standardUserDefaults] stringForKey:DONT_KEEP_MY_PRS_KEY] boolValue]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define HIDE_AVATARS_KEY @"HIDE_AVATARS_KEY"
-(void)setHideAvatars:(BOOL)hideAvatars { [self storeDefaultValue:@(hideAvatars) forKey:HIDE_AVATARS_KEY]; }
-(BOOL)hideAvatars { return [[[NSUserDefaults standardUserDefaults] stringForKey:HIDE_AVATARS_KEY] boolValue]; }

@end
