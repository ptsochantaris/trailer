#import "DetailViewController.h"

#define REFRESH_STARTED_NOTIFICATION @"RefreshStartedNotification"
#define REFRESH_ENDED_NOTIFICATION @"RefreshEndedNotification"
#define RECEIVED_NOTIFICATION_KEY @"ReceivedNotificationKey"

@interface MasterViewController : UITableViewController
<NSFetchedResultsControllerDelegate, UITextFieldDelegate,
UIActionSheetDelegate, UITabBarControllerDelegate>

@property (strong, nonatomic) DetailViewController *detailViewController;

@property (weak, nonatomic) IBOutlet UIBarButtonItem *refreshButton;

@property (strong, nonatomic) NSFetchedResultsController *fetchedResultsController;

- (void)reloadData;

@end
