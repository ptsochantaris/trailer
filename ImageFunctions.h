//
//  ImageFunctions.h
//  MyCommute
//
//  Created by Paul Tsochantaris on 9/2/13.
//  Copyright (c) 2013 Paul Tsochantaris. All rights reserved.
//

extern const CGBitmapInfo kDefaultCGBitmapInfo;
extern const CGBitmapInfo kDefaultCGBitmapInfoNoAlpha;

CGContextRef CreateContextFromImage(UIImage *image);

UIImage *GetImageFromContext(CGContextRef context);

float GetScaleForProportionalResize( CGSize theSize, CGSize intoSize, bool onlyScaleDown, bool maximize );

void CreateBufferFromImage( UIImage* image, unsigned char * buffer, NSInteger bitsPerChannel, NSInteger bytesPerRow, CGColorSpaceRef colorSpace );

CGContextRef CreateCGBitmapContextForWidthAndHeight( unsigned int width, unsigned int height,
													CGColorSpaceRef optionalColorSpace, CGBitmapInfo optionalInfo );

CGImageRef CreateCGImageFromUIImageScaled( UIImage* image, float scaleFactor, BOOL cropExtra );
