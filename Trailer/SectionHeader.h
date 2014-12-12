
@class SectionHeader;


@protocol SectionHeaderDelegate <NSObject>

- (void)sectionHeaderRemoveSelectedFrom:(SectionHeader *)item;

@end


@interface SectionHeader : NSTableRowView

@property (nonatomic,weak) id<SectionHeaderDelegate> delegate;

- (id)initWithDelegate:(id<SectionHeaderDelegate>)delegate title:(NSString *)title;

- (NSString *)title;

@end
