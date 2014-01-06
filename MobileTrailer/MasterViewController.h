
#define REFRESH_STARTED_NOTIFICATION @"RefreshStartedNotification"
#define REFRESH_ENDED_NOTIFICATION @"RefreshEndedNotification"
#define RECEIVED_NOTIFICATION_KEY @"ReceivedNotificationKey"

@class DetailViewController;

@interface MasterViewController : UITableViewController <NSFetchedResultsControllerDelegate>

@property (strong, nonatomic) DetailViewController *detailViewController;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *refreshButton;

@property (strong, nonatomic) NSFetchedResultsController *fetchedResultsController;
@property (strong, nonatomic) NSManagedObjectContext *managedObjectContext;

@end
