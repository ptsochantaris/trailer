
@class PickerViewController;

@protocol PickerViewControllerDelegate <NSObject>

- (void)pickerViewController:(PickerViewController *)picker
		   selectedIndexPath:(NSIndexPath *)indexPAth;

@end

@interface PickerViewController : UITableViewController

@property (nonatomic) NSArray *values;
@property (nonatomic, weak) id<PickerViewControllerDelegate> delegate;
@property (nonatomic) NSInteger previousValue;

@end
