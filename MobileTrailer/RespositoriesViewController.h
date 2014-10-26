
@interface RespositoriesViewController : UITableViewController

@property (nonatomic) NSFetchedResultsController *fetchedResultsController;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *actionsButton;

@end
