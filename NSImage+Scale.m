
@implementation NSImage (Scale)

- (NSImage *)scaleToFillSize:(CGSize)toSize
{
    NSRect targetFrame = NSMakeRect(0, 0, toSize.width, toSize.height);
    NSImageRep *sourceImageRep = [self bestRepresentationForRect:targetFrame
                                                         context:nil
                                                           hints:nil];

    NSImage *targetImage = [[NSImage alloc] initWithSize:toSize];
    [targetImage lockFocus];
    [sourceImageRep drawInRect: targetFrame];
    [targetImage unlockFocus];

	return targetImage;
}

@end
