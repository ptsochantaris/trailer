#ifndef Trailer_iOS_Globals_h
#define Trailer_iOS_Globals_h

#define COLOR_CLASS UIColor
#define IMAGE_CLASS UIImage
#define FONT_CLASS UIFont
#define MAKECOLOR(R,G,B,A) [COLOR_CLASS colorWithRed:R green:G blue:B alpha:A]

#ifdef DEBUG
#define DLog(fmt, ...) NSLog(fmt, ##__VA_ARGS__)
#else
#define DLog(...)
#endif

#endif
