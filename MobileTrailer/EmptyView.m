
@implementation EmptyView

- (id)initWithMessage:(NSAttributedString *)message
{
	CGSize idealSize = [message boundingRectWithSize:CGSizeMake(280, CGFLOAT_MAX)
											 options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading
											 context:nil].size;
	self = [super initWithFrame:CGRectMake(0, 0, 320, idealSize.height+10.0)];
	if(self)
	{
		UILabel *text = [[UILabel alloc] initWithFrame:CGRectMake((320-idealSize.width)*0.5, 5.0, idealSize.width, idealSize.height)];
		text.numberOfLines = 0;
		text.attributedText = message;
		[self addSubview:text];
	}
	return self;
}

@end
