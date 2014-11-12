
@interface ServerDetailViewController : UIViewController <UITextFieldDelegate>

@property (nonatomic) NSManagedObjectID *serverId;

@property (weak, nonatomic) IBOutlet UITextField *name;
@property (weak, nonatomic) IBOutlet UITextField *apiPath;
@property (weak, nonatomic) IBOutlet UITextField *webFrontEnd;
@property (weak, nonatomic) IBOutlet UITextField *authToken;
@property (weak, nonatomic) IBOutlet UISwitch *reportErrors;
@property (weak, nonatomic) IBOutlet UIScrollView *scrollView;
@property (weak, nonatomic) IBOutlet UILabel *authTokenLabel;
@property (weak, nonatomic) IBOutlet UIButton *testButton;

@end
