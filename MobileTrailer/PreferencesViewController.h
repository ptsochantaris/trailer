
@interface PreferencesViewController : UIViewController

@property (weak, nonatomic) IBOutlet UIProgressView *apiLoad;
@property (weak, nonatomic) IBOutlet UITextField *githubApiToken;
@property (weak, nonatomic) IBOutlet UITableView *repositories;
@property (nonatomic) NSFetchedResultsController *fetchedResultsController;
@property (weak, nonatomic) IBOutlet UILabel *instructionLabel;
@property (weak, nonatomic) IBOutlet UIButton *createTokenButton;
@property (weak, nonatomic) IBOutlet UIButton *viewTokensButton;
@property (weak, nonatomic) IBOutlet UILabel *apiUsageLabel;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *refreshRepoList;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *watchListButton;

@end
