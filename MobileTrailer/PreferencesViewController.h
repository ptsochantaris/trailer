
@interface PreferencesViewController : UIViewController

@property (weak, nonatomic) IBOutlet UIProgressView *apiLoad;
@property (weak, nonatomic) IBOutlet UITextField *githubApiToken;
@property (weak, nonatomic) IBOutlet UILabel *versionNumber;
@property (weak, nonatomic) IBOutlet UITableView *repositories;
@property (weak, nonatomic) IBOutlet UIButton *refreshRepoList;
@property (strong, nonatomic) NSFetchedResultsController *fetchedResultsController;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *selectionButton;
@property (weak, nonatomic) IBOutlet UILabel *instructionLabel;
@property (weak, nonatomic) IBOutlet UIButton *createTokenButton;
@property (weak, nonatomic) IBOutlet UIButton *viewTokensButton;
@property (weak, nonatomic) IBOutlet UILabel *apiUsageLabel;
@property (weak, nonatomic) IBOutlet UIButton *advancedButton;

@end
