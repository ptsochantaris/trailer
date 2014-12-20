
@interface MasterViewController : UITableViewController
<NSFetchedResultsControllerDelegate, UITextFieldDelegate,
UIActionSheetDelegate, UITabBarControllerDelegate>

@property (strong, nonatomic) DetailViewController *detailViewController;

@property (weak, nonatomic) IBOutlet UIBarButtonItem *refreshButton;

@property (strong, nonatomic) NSFetchedResultsController *fetchedResultsController;

- (void)reloadData;

@end
