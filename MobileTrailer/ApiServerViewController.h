
@interface ApiServerViewController : UIViewController

@property (weak, nonatomic) IBOutlet UITextField *apiFrontEnd;
@property (weak, nonatomic) IBOutlet UITextField *apiBackEnd;
@property (weak, nonatomic) IBOutlet UITextField *apiPath;

@property (weak, nonatomic) IBOutlet UIBarButtonItem *testApiButton;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *restoreDefaultsButton;

@end
