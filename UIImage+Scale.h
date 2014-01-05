extern CGFloat GLOBAL_SCREEN_SCALE;
#define GLOBAL_INTERPOLATION_QUALITY kCGInterpolationMedium

@interface UIImage (scale)

- (UIImage *)scaleToSize:(CGSize)toSize;

- (UIImage *)scaleToFillSize:(CGSize)toSize;

- (UIImage *)scaleToPixelSize:(CGSize)toSize fill:(BOOL)fillInsteadOfFit;

- (UIImage *)scaleToFillPixelSize:(CGSize)toSize;

- (UIImage *)stretchToPixelSize:(CGSize)toSize quality:(CGInterpolationQuality)quality;

@end

