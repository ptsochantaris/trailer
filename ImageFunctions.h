
extern const CGBitmapInfo kDefaultCGBitmapInfo;
extern const CGBitmapInfo kDefaultCGBitmapInfoNoAlpha;

CGContextRef CreateContextFromImage(UIImage *image);

UIImage *GetImageFromContext(CGContextRef context);

float GetScaleForProportionalResize( CGSize theSize, CGSize intoSize, bool onlyScaleDown, bool maximize );

void CreateBufferFromImage( UIImage* image, unsigned char * buffer, NSInteger bitsPerChannel, NSInteger bytesPerRow, CGColorSpaceRef colorSpace );

CGContextRef CreateCGBitmapContextForWidthAndHeight( unsigned int width, unsigned int height,
													CGColorSpaceRef optionalColorSpace, CGBitmapInfo optionalInfo );

CGImageRef CreateCGImageFromUIImageScaled( UIImage* image, float scaleFactor, BOOL cropExtra );
