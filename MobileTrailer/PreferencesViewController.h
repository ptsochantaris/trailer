
@interface PreferencesViewController : UIViewController

@property (weak, nonatomic) IBOutlet UIProgressView *apiLoad;
@property (weak, nonatomic) IBOutlet UITextField *githubApiToken;
@property (weak, nonatomic) IBOutlet UILabel *versionNumber;
@property (weak, nonatomic) IBOutlet UITableView *repositories;
@property (weak, nonatomic) IBOutlet UIButton *refreshRepoList;

@property (strong, nonatomic) NSFetchedResultsController *fetchedResultsController;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *selectionButton;

@end
