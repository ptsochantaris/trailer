
@interface AppDelegate : NSObject <
	NSApplicationDelegate,
	NSTableViewDelegate,
	NSTableViewDataSource,
	NSWindowDelegate,
	NSUserNotificationCenterDelegate,
	PRItemViewDelegate,
	SectionHeaderDelegate,
	StatusItemDelegate
>

// Preferences window
@property (unsafe_unretained) IBOutlet NSWindow *preferencesWindow;
@property (weak) IBOutlet NSButton *refreshButton;
@property (weak) IBOutlet NSTextField *githubTokenHolder;
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
@property (weak) IBOutlet NSButton *hideAvatars;
@property (weak) IBOutlet NSButton *autoParticipateWhenMentioned;
@property (weak) IBOutlet NSButton *keepClosedPrs;
@property (weak) IBOutlet NSButton *dontConfirmRemoveAllMerged;
@property (weak) IBOutlet NSButton *dontConfirmRemoveAllClosed;
@property (weak) IBOutlet NSButton *displayRepositoryNames;
@property (weak) IBOutlet NSButton *includeRepositoriesInFiltering;
@property (weak) IBOutlet NSButton *dontReportRefreshFailures;
@property (weak) IBOutlet NSButton *groupByRepo;
@property (weak) IBOutlet NSButton *hideAllPrsSection;

// About window
@property (weak) IBOutlet NSTextField *aboutVersion;

// API widow
@property (unsafe_unretained) IBOutlet NSWindow *apiSettings;
@property (weak) IBOutlet NSTextField *apiFrontEnd;
@property (weak) IBOutlet NSTextField *apiBackEnd;
@property (weak) IBOutlet NSTextField *apiPath;

// Used to track action state
@property (nonatomic) BOOL opening;

// Menu
@property (nonatomic) NSStatusItem *statusItem;
@property (nonatomic) StatusItemView *statusItemView;
@property (unsafe_unretained) IBOutlet MenuWindow *mainMenu;
@property (weak) IBOutlet NSSearchField *mainMenuFilter;
@property (nonatomic) HTPopTimer *filterTimer;

// Globals
@property (nonatomic) API *api;
@property (nonatomic) DataManager *dataManager;
@property (weak) NSTimer *refreshTimer;
@property (strong) NSDate *lastSuccessfulRefresh;
@property (nonatomic) BOOL lastUpdateFailed, preferencesDirty;
@property (nonatomic, readonly) BOOL isRefreshing, menuIsOpen;

+(AppDelegate*)shared;

-(void)postNotificationOfType:(PRNotificationType)type forItem:(id)item;

@end
