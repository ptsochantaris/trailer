
#import "PRItemView.h"
#import "SectionHeader.h"
#import "StatusItemView.h"
#import "MenuWindow.h"
#import "API.h"

@class PopTimer, DataManager;

@interface OSX_AppDelegate : NSObject <
	NSApplicationDelegate,
	NSTableViewDelegate,
	NSTableViewDataSource,
	NSTabViewDelegate,
	NSWindowDelegate,
	NSUserNotificationCenterDelegate,
	PRItemViewDelegate,
	SectionHeaderDelegate,
	StatusItemDelegate
>

// Preferences window
@property (unsafe_unretained) IBOutlet NSWindow *preferencesWindow;
@property (weak) IBOutlet NSButton *refreshButton;
@property (weak) IBOutlet NSProgressIndicator *activityDisplay;
@property (weak) IBOutlet NSTableView *projectsTable;
@property (weak) IBOutlet NSMenuItem *refreshNow;
@property (weak) IBOutlet NSTextField *versionNumber;
@property (weak) IBOutlet NSButton *launchAtStartup;
@property (weak) IBOutlet NSTextField *refreshDurationLabel;
@property (weak) IBOutlet NSStepper *refreshDurationStepper;
@property (weak) IBOutlet NSButton *hideUncommentedPrs;
@property (weak) IBOutlet NSTextField *repoFilter;
@property (weak) IBOutlet NSButton *showAllComments;
@property (weak) IBOutlet NSButton *sortingOrder;
@property (weak) IBOutlet NSPopUpButton *sortModeSelect;
@property (weak) IBOutlet NSButton *showCreationDates;
@property (weak) IBOutlet NSButton *dontKeepPrsMergedByMe;
@property (weak) IBOutlet NSButton *hideAvatars;
@property (weak) IBOutlet NSButton *autoParticipateWhenMentioned;
@property (weak) IBOutlet NSButton *dontConfirmRemoveAllMerged;
@property (weak) IBOutlet NSButton *dontConfirmRemoveAllClosed;
@property (weak) IBOutlet NSButton *displayRepositoryNames;
@property (weak) IBOutlet NSButton *includeRepositoriesInFiltering;
@property (weak) IBOutlet NSButton *dontReportRefreshFailures;
@property (weak) IBOutlet NSButton *groupByRepo;
@property (weak) IBOutlet NSButton *hideAllPrsSection;
@property (weak) IBOutlet NSButton *showStatusItems;
@property (weak) IBOutlet NSButton *makeStatusItemsSelectable;
@property (weak) IBOutlet NSPopUpButton *statusTermMenu;
@property (weak) IBOutlet NSTokenField *statusTermsField;
@property (weak) IBOutlet NSButton *moveAssignedPrsToMySection;
@property (weak) IBOutlet NSButton *markUnmergeableOnUserSectionsOnly;
@property (weak) IBOutlet NSTextField *repoCheckLabel;
@property (weak) IBOutlet NSStepper *repoCheckStepper;
@property (weak) IBOutlet NSButton *countOnlyListedPrs;
@property (weak) IBOutlet NSPopUpButton *prMergedPolicy;
@property (weak) IBOutlet NSPopUpButton *prClosedPolicy;
@property (weak) IBOutlet NSButton *checkForUpdatesAutomatically;
@property (weak) IBOutlet NSTextField *checkForUpdatesLabel;
@property (weak) IBOutlet NSStepper *checkForUpdatesSelector;
@property (weak) IBOutlet NSTextField *statusItemRescanLabel;
@property (weak) IBOutlet NSStepper *statusItemRefreshCounter;
@property (weak) IBOutlet NSTextField *statusItemsRefreshNote;
@property (weak) IBOutlet NSButton *hideNewRepositories;
@property (weak) IBOutlet NSButton *openPrAtFirstUnreadComment;
@property (weak) IBOutlet NSButton *logActivityToConsole;
@property (weak) IBOutlet NSTokenField *commentAuthorBlacklist;
@property (weak) IBOutlet NSButton *showLabels;

// Preferences - Display
@property (weak) IBOutlet NSButton *useVibrancy;

// Preferences - Labels
@property (weak) IBOutlet NSTextField *labelRescanLabel;
@property (weak) IBOutlet NSTextField *labelRefreshNote;
@property (weak) IBOutlet NSStepper *labelRefreshCounter;

// Preferences - Servers
@property (weak) IBOutlet NSTableView *serverList;
@property (weak) IBOutlet NSTextField *apiServerName;
@property (weak) IBOutlet NSTextField *apiServerApiPath;
@property (weak) IBOutlet NSTextField *apiServerWebPath;
@property (weak) IBOutlet NSTextField *apiServerAuthToken;
@property (weak) IBOutlet NSBox *apiServerSelectedBox;
@property (weak) IBOutlet NSButton *apiServerTestButton;
@property (weak) IBOutlet NSButton *apiServerDeleteButton;
@property (weak) IBOutlet NSButton *apiServerReportError;

// Keyboard
@property (weak) IBOutlet NSButton *hotkeyEnable;
@property (weak) IBOutlet NSButton *hotkeyCommandModifier;
@property (weak) IBOutlet NSButton *hotkeyOptionModifier;
@property (weak) IBOutlet NSButton *hotkeyShiftModifier;
@property (weak) IBOutlet NSPopUpButton *hotkeyLetter;
@property (weak) IBOutlet NSTextField *hotKeyHelp;
@property (weak) IBOutlet NSBox *hotKeyContainer;
@property (weak) IBOutlet NSButton *hotkeyControlModifier;

// About window
@property (weak) IBOutlet NSTextField *aboutVersion;

// Used to track action state
@property (nonatomic) BOOL opening;

// Menu
@property (nonatomic) NSStatusItem *statusItem;
@property (nonatomic) StatusItemView *statusItemView;
@property (unsafe_unretained) IBOutlet MenuWindow *mainMenu;
@property (weak) IBOutlet NSSearchField *mainMenuFilter;
@property (nonatomic) PopTimer *filterTimer;

// Globals
@property (nonatomic) API *api;
@property (nonatomic) DataManager *dataManager;
@property (weak) NSTimer *refreshTimer;
@property (strong) NSDate *lastSuccessfulRefresh, *lastRepoCheck;
@property (nonatomic) BOOL preferencesDirty, isRefreshing, isManuallyScrolling, ignoreNextFocusLoss;
@property (nonatomic, readonly) BOOL menuIsOpen;
@property (nonatomic) long highlightedPrIndex;
@property (nonatomic) float scrollBarWidth;
@property (nonatomic) NSString *currentAppVersion;


- (void)postNotificationOfType:(PRNotificationType)type forItem:(id)item;

- (NSString *)focusedItemUrl;

@end

extern OSX_AppDelegate *app;
