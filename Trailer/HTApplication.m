
@implementation HTApplication

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"

- (void)sendEvent:(NSEvent *)event
{
    if(event.type == NSKeyDown)
	{
        if(([event modifierFlags] & NSDeviceIndependentModifierFlagsMask) == NSCommandKeyMask)
		{
            if([event.charactersIgnoringModifiers isEqualToString:@"x"])
			{
                if([self sendAction:@selector(cut:) to:nil from:self]) return;
            }
            else if([event.charactersIgnoringModifiers isEqualToString:@"c"])
			{
				NSString *url = [AppDelegate shared].focusedItemUrl;
				if(url)
				{
					NSPasteboard *p = [NSPasteboard generalPasteboard];
					[p clearContents];
					[p setString:url forType:NSStringPboardType];
				}
				else
				{
					if([self sendAction:@selector(copy:) to:nil from:self]) return;
				}
            }
            else if([event.charactersIgnoringModifiers isEqualToString:@"v"])
			{
                if([self sendAction:@selector(paste:) to:nil from:self]) return;
            }
            else if([event.charactersIgnoringModifiers isEqualToString:@"z"])
			{
                if([self sendAction:@selector(undo:) to:nil from:self]) return;
            }
            else if([event.charactersIgnoringModifiers isEqualToString:@"a"])
			{
                if([self sendAction:@selector(selectAll:) to:nil from:self]) return;
            }
        }
        else if(([event modifierFlags] & NSDeviceIndependentModifierFlagsMask) == (NSCommandKeyMask | NSShiftKeyMask))
		{
            if ([event.charactersIgnoringModifiers isEqualToString:@"Z"])
			{
                if ([self sendAction:@selector(redo:) to:nil from:self]) return;
            }
        }
    }
    [super sendEvent:event];
}

#pragma clang diagnostic pop

@end
