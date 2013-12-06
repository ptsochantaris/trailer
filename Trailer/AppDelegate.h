//
//  AppDelegate.h
//  Trailer
//
//  Created by Paul Tsochantaris on 20/09/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

#define LOW_API_WARNING 0.90

typedef enum {
	kNewComment = 0,
	kNewPr = 1,
	kPrMerged = 2
} PRNotificationType;

typedef enum {
	kCreationDate = 0,
	kRecentActivity = 1,
	kTitle= 2
} PRSortingMethod;

@interface AppDelegate : NSObject <
	NSApplicationDelegate,
	NSTableViewDelegate,
	NSTableViewDataSource,
	NSWindowDelegate,
	NSUserNotificationCenterDelegate,
	NSMenuDelegate,
	PRItemViewDelegate,
	SectionHeaderDelegate
>

// Core Data
@property (readonly, strong, nonatomic) NSPersistentStoreCoordinator *persistentStoreCoordinator;
@property (readonly, strong, nonatomic) NSManagedObjectModel *managedObjectModel;
@property (readonly, strong, nonatomic) NSManagedObjectContext *managedObjectContext;
@property (unsafe_unretained) IBOutlet NSWindow *preferencesWindow;

// Preferences window
@property (weak) IBOutlet NSButton *refreshButton;
@property (weak) IBOutlet NSTextField *githubTokenHolder;
@property (weak) IBOutlet NSMenu *statusBarMenu;
@property (weak) IBOutlet NSProgressIndicator *activityDisplay;
@property (weak) IBOutlet NSTableView *projectsTable;
@property (weak) IBOutlet NSMenuItem *refreshNow;
@property (weak) IBOutlet NSButton *clearAll;
@property (weak) IBOutlet NSButton *selectAll;
@property (weak) IBOutlet NSProgressIndicator *apiLoad;
@property (weak) IBOutlet NSTextField *versionNumber;
@property (weak) IBOutlet NSButton *launchAtStartup;
@property (weak) IBOutlet NSTextField *refreshDurationLabel;
@property (weak) IBOutlet NSStepper *refreshDurationStepper;
@property (weak) IBOutlet NSButton *hideUncommentedPrs;
@property (weak) IBOutlet NSTextField *repoFilter;
@property (weak) IBOutlet NSButton *showAllComments;
@property (weak) IBOutlet NSBox *githubDetailsBox;
@property (weak) IBOutlet NSButton *sortingOrder;
@property (weak) IBOutlet NSPopUpButton *sortModeSelect;
@property (weak) IBOutlet NSButton *showCreationDates;
@property (weak) IBOutlet NSButton *dontKeepMyPrs;

// Menu sections
@property (strong) IBOutlet NSMenuItem *menuMyHeader;
@property (strong) IBOutlet NSMenuItem *menuParticipatedHeader;
@property (strong) IBOutlet NSMenuItem *menuMergedHeader;
@property (strong) IBOutlet NSMenuItem *menuAllHeader;
@property (weak) IBOutlet NSMenuItem *menuOptions;

// Globals
@property (nonatomic) API *api;
@property (weak) NSTimer *refreshTimer;
@property (nonatomic) NSStatusItem *statusItem;
@property (strong) NSDate *lastSuccessfulRefresh;
@property (nonatomic) BOOL lastUpdateFailed, preferencesDirty;
@property (nonatomic, readonly) BOOL isRefreshing, menuIsOpen;

+(AppDelegate*)shared;

-(void)postNotificationOfType:(PRNotificationType)type forItem:(id)item;

@end
