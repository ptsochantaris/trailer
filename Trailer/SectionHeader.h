
@class SectionHeader;


@protocol SectionHeaderDelegate <NSObject>

- (void)sectionHeaderRemoveSelectedFrom:(SectionHeader *)item;

@end


@interface SectionHeader : NSView

@property (nonatomic,weak) id<SectionHeaderDelegate> delegate;

- (id)initWithRemoveAllDelegate:(id<SectionHeaderDelegate>)delegate title:(NSString *)title;

@end
