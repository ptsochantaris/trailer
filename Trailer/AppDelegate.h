
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
@property (strong) NSDate *lastSuccessfulRefresh, *lastRepoCheck;
@property (nonatomic) BOOL lastUpdateFailed, preferencesDirty, isRefreshing, isManuallyScrolling, ignoreNextFocusLoss;
@property (nonatomic, readonly) BOOL menuIsOpen;
@property (nonatomic) long highlightedPrIndex;
@property (nonatomic) float scrollBarWidth;
@property (nonatomic) NSString *currentAppVersion;


+ (AppDelegate*)shared;

- (void)postNotificationOfType:(PRNotificationType)type forItem:(id)item;

- (NSString *)focusedItemUrl;

@end
