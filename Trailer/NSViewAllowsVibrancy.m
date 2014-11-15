
@implementation NSViewAllowsVibrancy

- (void)awakeFromNib
{
	[super awakeFromNib];
	self.wantsLayer = YES;
}

- (BOOL)allowsVibrancy { return YES; }

@end
