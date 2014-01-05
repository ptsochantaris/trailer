//
//  ImageFunctions.m
//  MyCommute
//
//  Created by Paul Tsochantaris on 9/2/13.
//  Copyright (c) 2013 Paul Tsochantaris. All rights reserved.
//

const double		kRadPerDeg	= 0.0174532925199433;	// pi / 180

const CGBitmapInfo kDefaultCGBitmapInfo	= (kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
const CGBitmapInfo kDefaultCGBitmapInfoNoAlpha	= (kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Host);

CGColorSpaceRef	GetDeviceRGBColorSpace() {
	static CGColorSpaceRef	deviceRGBSpace	= NULL;
	if( deviceRGBSpace == NULL )
		deviceRGBSpace	= CGColorSpaceCreateDeviceRGB();
	return deviceRGBSpace;
}

float GetScaleForProportionalResize( CGSize theSize, CGSize intoSize, bool onlyScaleDown, bool maximize )
{
	float	sx = theSize.width;
	float	sy = theSize.height;
	float	dx = intoSize.width;
	float	dy = intoSize.height;
	float	scale	= 1;
	
	if( sx != 0 && sy != 0 )
	{
		dx	= dx / sx;
		dy	= dy / sy;
		
		// if maximize is true, take LARGER of the scales, else smaller
		if( maximize )		scale	= (dx > dy)	? dx : dy;
		else				scale	= (dx < dy)	? dx : dy;
		
		if( scale > 1 && onlyScaleDown )	// reset scale
			scale	= 1;
	}
	else
	{
		scale	 = 0;
	}
	return scale;
}

CGContextRef CreateCGBitmapContextForWidthAndHeight( unsigned int width, unsigned int height,
													CGColorSpaceRef optionalColorSpace, CGBitmapInfo optionalInfo )
{
	CGColorSpaceRef	colorSpace	= (optionalColorSpace == NULL) ? GetDeviceRGBColorSpace() : optionalColorSpace;
	CGBitmapInfo	alphaInfo	= ( (int32_t)optionalInfo < 0 ) ? kDefaultCGBitmapInfo : optionalInfo;
	return CGBitmapContextCreate( NULL, width, height, 8, 0, colorSpace, alphaInfo );
}

CGImageRef CreateCGImageFromUIImageScaled( UIImage* image, float scaleFactor, BOOL cropExtra )
{
	CGImageRef			newImage		= NULL;
	CGContextRef		bmContext		= NULL;
	BOOL				mustTransform	= YES;
	CGAffineTransform	transform		= CGAffineTransformIdentity;
	UIImageOrientation	orientation		= image.imageOrientation;
	
	CGImageRef			srcCGImage		= CGImageRetain( image.CGImage );
	
	size_t width	= CGImageGetWidth(srcCGImage) * scaleFactor;
	size_t height	= CGImageGetHeight(srcCGImage) * scaleFactor;
    size_t ow = width;
    size_t oh = height;
    
    if(cropExtra)
    {
        size_t x = MIN(width,height);
        width = x;
        height = x;
    }
	
	// These Orientations are rotated 0 or 180 degrees, so they retain the width/height of the image
	if( (orientation == UIImageOrientationUp) || (orientation == UIImageOrientationDown) || (orientation == UIImageOrientationUpMirrored) || (orientation == UIImageOrientationDownMirrored)  )
	{
		bmContext	= CreateCGBitmapContextForWidthAndHeight( (unsigned int)width, (unsigned int)height, NULL, kDefaultCGBitmapInfo );
	}
	else	// The other Orientations are rotated ±90 degrees, so they swap width & height.
	{
		bmContext	= CreateCGBitmapContextForWidthAndHeight( (unsigned int)height, (unsigned int)width, NULL, kDefaultCGBitmapInfo );
	}
	
	CGContextSetInterpolationQuality( bmContext, GLOBAL_INTERPOLATION_QUALITY );
	CGContextSetBlendMode( bmContext, kCGBlendModeCopy );	// we just want to copy the data
	
	switch(orientation)
	{
		case UIImageOrientationDown:		// 0th row is at the bottom, and 0th column is on the right - Rotate 180 degrees
			transform	= CGAffineTransformMake(-1.0, 0.0, 0.0, -1.0, width, height);
			break;
			
		case UIImageOrientationLeft:		// 0th row is on the left, and 0th column is the bottom - Rotate -90 degrees
			transform	= CGAffineTransformMake(0.0, 1.0, -1.0, 0.0, height, 0.0);
			break;
			
		case UIImageOrientationRight:		// 0th row is on the right, and 0th column is the top - Rotate 90 degrees
			transform	= CGAffineTransformMake(0.0, -1.0, 1.0, 0.0, 0.0, width);
			break;
			
		case UIImageOrientationUpMirrored:	// 0th row is at the top, and 0th column is on the right - Flip Horizontal
			transform	= CGAffineTransformMake(-1.0, 0.0, 0.0, 1.0, width, 0.0);
			break;
			
		case UIImageOrientationDownMirrored:	// 0th row is at the bottom, and 0th column is on the left - Flip Vertical
			transform	= CGAffineTransformMake(1.0, 0.0, 0, -1.0, 0.0, height);
			break;
			
		case UIImageOrientationLeftMirrored:	// 0th row is on the left, and 0th column is the top - Rotate -90 degrees and Flip Vertical
			transform	= CGAffineTransformMake(0.0, -1.0, -1.0, 0.0, height, width);
			break;
			
		case UIImageOrientationRightMirrored:	// 0th row is on the right, and 0th column is the bottom - Rotate 90 degrees and Flip Vertical
			transform	= CGAffineTransformMake(0.0, 1.0, 1.0, 0.0, 0.0, 0.0);
			break;
			
		default:
			mustTransform	= NO;
			break;
	}
	
	if( mustTransform )	CGContextConcatCTM( bmContext, transform );
    
    NSInteger dx = width-ow;
    NSInteger dy = height-oh;
	CGContextDrawImage( bmContext, CGRectMake(dx*0.5, dy*0.5, ow, oh), srcCGImage );
	CGImageRelease( srcCGImage );
	newImage = CGBitmapContextCreateImage( bmContext );
	CFRelease( bmContext );
	
	return newImage;
}

void CreateBufferFromImage( UIImage* image, unsigned char * buffer, NSInteger bitsPerChannel, NSInteger bytesPerRow, CGColorSpaceRef colorSpace )
{
	CGContextRef		bmContext		= NULL;
	BOOL				mustTransform	= YES;
	CGAffineTransform	transform		= CGAffineTransformIdentity;
	UIImageOrientation	orientation		= image.imageOrientation;
	
	CGImageRef			srcCGImage		= CGImageRetain( image.CGImage );
	
	size_t width	= CGImageGetWidth(srcCGImage);
	size_t height	= CGImageGetHeight(srcCGImage);
	
	// These Orientations are rotated 0 or 180 degrees, so they retain the width/height of the image
	if( (orientation == UIImageOrientationUp) || (orientation == UIImageOrientationDown) || (orientation == UIImageOrientationUpMirrored) || (orientation == UIImageOrientationDownMirrored)  )
	{
        bmContext = CGBitmapContextCreate(buffer, width, height, bitsPerChannel, bytesPerRow, colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	}
	else	// The other Orientations are rotated ±90 degrees, so they swap width & height.
	{
        bmContext = CGBitmapContextCreate(buffer, height, width, bitsPerChannel, bytesPerRow, colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
	}
	
	CGContextSetInterpolationQuality( bmContext, GLOBAL_INTERPOLATION_QUALITY );
	CGContextSetBlendMode( bmContext, kCGBlendModeCopy );	// we just want to copy the data
	
	switch(orientation)
	{
		case UIImageOrientationDown:		// 0th row is at the bottom, and 0th column is on the right - Rotate 180 degrees
			transform	= CGAffineTransformMake(-1.0, 0.0, 0.0, -1.0, width, height);
			break;
			
		case UIImageOrientationLeft:		// 0th row is on the left, and 0th column is the bottom - Rotate -90 degrees
			transform	= CGAffineTransformMake(0.0, 1.0, -1.0, 0.0, height, 0.0);
			break;
			
		case UIImageOrientationRight:		// 0th row is on the right, and 0th column is the top - Rotate 90 degrees
			transform	= CGAffineTransformMake(0.0, -1.0, 1.0, 0.0, 0.0, width);
			break;
			
		case UIImageOrientationUpMirrored:	// 0th row is at the top, and 0th column is on the right - Flip Horizontal
			transform	= CGAffineTransformMake(-1.0, 0.0, 0.0, 1.0, width, 0.0);
			break;
			
		case UIImageOrientationDownMirrored:	// 0th row is at the bottom, and 0th column is on the left - Flip Vertical
			transform	= CGAffineTransformMake(1.0, 0.0, 0, -1.0, 0.0, height);
			break;
			
		case UIImageOrientationLeftMirrored:	// 0th row is on the left, and 0th column is the top - Rotate -90 degrees and Flip Vertical
			transform	= CGAffineTransformMake(0.0, -1.0, -1.0, 0.0, height, width);
			break;
			
		case UIImageOrientationRightMirrored:	// 0th row is on the right, and 0th column is the bottom - Rotate 90 degrees and Flip Vertical
			transform	= CGAffineTransformMake(0.0, 1.0, 1.0, 0.0, 0.0, 0.0);
			break;
			
		default:
			mustTransform	= NO;
			break;
	}
	
	if( mustTransform )	CGContextConcatCTM( bmContext, transform );
	
	CGContextDrawImage( bmContext, CGRectMake(0.0, 0.0, width, height), srcCGImage );
	CGImageRelease( srcCGImage );
	CFRelease( bmContext );
}

UIImage* UImageFromPathScaledToSize(NSString* path, CGSize toSize)
{
	UIImage	*scaledImg	= nil;
	UIImage	*img = [[UIImage alloc] initWithContentsOfFile:path];	// get the image
	
	if( img )
	{
		float	scale	= GetScaleForProportionalResize( img.size, toSize, false, false );
		
		CGImageRef cgImage	= CreateCGImageFromUIImageScaled( img, scale, NO );
		
		
		if( cgImage )
		{
			scaledImg	= [UIImage imageWithCGImage:cgImage];	// autoreleased
			CGImageRelease( cgImage );
		}
	}
	return scaledImg;	// autoreleased
}

CGContextRef CreateContextFromImage(UIImage *image)
{
    CGImageRef imageRef = image.CGImage;
    size_t pixelsWide = CGImageGetWidth(imageRef);
    size_t pixelsHigh = CGImageGetHeight(imageRef);
    
    CGContextRef context = CreateCGBitmapContextForWidthAndHeight((unsigned int)pixelsWide, (unsigned int)pixelsHigh, NULL, kDefaultCGBitmapInfo);
    CGRect rect = CGRectMake(0, 0, pixelsWide, pixelsHigh);
    CGContextDrawImage(context, rect, imageRef);
    
    return context;
}

UIImage *GetImageFromContext(CGContextRef context)
{
    CGImageRef mCGImage = CGBitmapContextCreateImage(context);
    UIImage * mUIImage = [UIImage imageWithCGImage: mCGImage];
    CGImageRelease(mCGImage);
    return mUIImage;
}
