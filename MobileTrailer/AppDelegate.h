//
//  AppDelegate.h
//  MobileTrailer
//
//  Created by Paul Tsochantaris on 4/1/14.
//  Copyright (c) 2014 HouseTrip. All rights reserved.
//

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow *window;

@property (nonatomic) API *api;
@property (nonatomic) DataManager *dataManager;
@property (nonatomic) HTPopTimer *filterTimer;
@property (nonatomic) BOOL preferencesDirty, isRefreshing, lastUpdateFailed;
@property (nonatomic) NSDate *lastSuccessfulRefresh;
@property (nonatomic) NSTimer *refreshTimer;

+ (AppDelegate *)shared;

- (void)postNotificationOfType:(PRNotificationType)type forItem:(id)item;

- (void)startRefresh;

- (void)forcePreferences;

@end
