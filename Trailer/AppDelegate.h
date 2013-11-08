//
//  AppDelegate.h
//  Trailer
//
//  Created by Paul Tsochantaris on 20/09/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

#define LOW_API_WARNING 1000

typedef enum {
	kNewComment,
	kNewPr,
	kPrMerged
} PRNotificationType;

@interface AppDelegate : NSObject <NSApplicationDelegate,
NSTableViewDelegate, NSTableViewDataSource, NSWindowDelegate,
NSUserNotificationCenterDelegate, NSMenuDelegate>

@property (readonly, strong, nonatomic) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@property (readonly, strong, nonatomic) NSManagedObjectModel *managedObjectModel;
@property (readonly, strong, nonatomic) NSManagedObjectContext *managedObjectContext;
@property (unsafe_unretained) IBOutlet NSWindow *preferencesWindow;

@property (nonatomic) API *api;
@property (nonatomic) NSStatusItem *statusItem;
@property (weak) IBOutlet NSButton *refreshButton;
@property (weak) IBOutlet NSTextField *githubTokenHolder;
@property (weak) IBOutlet NSMenu *statusBarMenu;
@property (weak) IBOutlet NSProgressIndicator *activityDisplay;
@property (weak) IBOutlet NSTableView *projectsTable;
@property (weak) IBOutlet NSMenuItem *refreshNow;
@property (weak) IBOutlet NSButton *clearAll;
@property (weak) IBOutlet NSButton *selectAll;
@property (weak) IBOutlet NSProgressIndicator *apiLoad;
@property (weak) IBOutlet NSTextField *userNameLabel;
@property (weak) IBOutlet NSTextField *versionNumber;
@property (weak) NSTimer *refreshTimer;
@property (weak) IBOutlet NSButton *launchAtStartup;
@property (nonatomic) BOOL lastUpdateFailed;
@property (weak) IBOutlet NSTextField *refreshDurationLabel;
@property (weak) IBOutlet NSStepper *refreshDurationStepper;

@property (strong) NSMutableArray *prMenuItems;
@property (strong) NSDate *lastSuccessfulRefresh;

+(AppDelegate*)shared;

-(void)postNotificationOfType:(PRNotificationType)type forItem:(id)item;

@end
