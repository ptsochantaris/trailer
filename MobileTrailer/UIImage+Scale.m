
@implementation UIImage (scale)

- (UIImage *)scaleToSize:(CGSize)toSize
{
	UIImage	*scaledImg	= nil;
	float	scale		= GetScaleForProportionalResize( self.size, toSize, false, false )*GLOBAL_SCREEN_SCALE;
	CGImageRef cgImage	= CreateCGImageFromUIImageScaled( self, scale, NO );
			
	if( cgImage )
	{
		scaledImg	= [UIImage imageWithCGImage:cgImage scale:GLOBAL_SCREEN_SCALE orientation:UIImageOrientationUp];	// autoreleased
		CGImageRelease( cgImage );
	}
	return scaledImg;
}

- (UIImage *)scaleToPixelSize:(CGSize)toSize fill:(BOOL)fillInsteadOfFit
{
	UIImage	*scaledImg	= nil;
	float	scale		= GetScaleForProportionalResize( self.size, toSize, false, fillInsteadOfFit );
	CGImageRef cgImage	= CreateCGImageFromUIImageScaled( self, scale, fillInsteadOfFit );
        
	if( cgImage )
	{
		scaledImg	= [UIImage imageWithCGImage:cgImage scale:1.0 orientation:UIImageOrientationUp];	// autoreleased
		CGImageRelease( cgImage );
	}
	return scaledImg;
}

- (UIImage *)scaleToFillSize:(CGSize)toSize
{
	UIImage	*scaledImg	= nil;
	float	scale		= GetScaleForProportionalResize( self.size, toSize, false, true )*GLOBAL_SCREEN_SCALE;
	CGImageRef cgImage	= CreateCGImageFromUIImageScaled( self, scale, NO );
    
	if( cgImage )
	{
		scaledImg	= [UIImage imageWithCGImage:cgImage scale:GLOBAL_SCREEN_SCALE orientation:UIImageOrientationUp];	// autoreleased
		CGImageRelease( cgImage );
	}
	return scaledImg;
}

- (UIImage *)scaleToFillPixelSize:(CGSize)toSize
{
	UIImage	*scaledImg	= nil;
	float	scale		= GetScaleForProportionalResize( self.size, toSize, false, true );
	CGImageRef cgImage	= CreateCGImageFromUIImageScaled( self, scale, NO );
    
	if( cgImage )
	{
		scaledImg	= [UIImage imageWithCGImage:cgImage scale:1.0 orientation:UIImageOrientationUp];	// autoreleased
		CGImageRelease( cgImage );
	}
	return scaledImg;
}

- (UIImage *)stretchToPixelSize:(CGSize)toSize quality:(CGInterpolationQuality)quality
{
    CGContextRef context = CreateCGBitmapContextForWidthAndHeight(toSize.width, toSize.height, NULL, kDefaultCGBitmapInfo);
    CGRect rect = CGRectMake(0, 0, toSize.width, toSize.height);
    CGContextSetInterpolationQuality(context, quality);
    CGContextDrawImage(context, rect, self.CGImage);
        
    CGImageRef cgImage = CGBitmapContextCreateImage(context);
    UIImage *scaled = [UIImage imageWithCGImage:cgImage scale:1.0 orientation:UIImageOrientationUp];
    CGImageRelease(cgImage);
    CGContextRelease(context);
    return scaled;
}

@end
