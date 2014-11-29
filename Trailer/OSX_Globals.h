#ifndef Trailer_OSX_Globals_h
#define Trailer_OSX_Globals_h

#define MENU_WIDTH 500.0
#define COLOR_CLASS NSColor
#define IMAGE_CLASS NSImage
#define FONT_CLASS NSFont
#define MAKECOLOR(R,G,B,A) [COLOR_CLASS colorWithSRGBRed:R green:G blue:B alpha:A]

#ifdef DEBUG
#define DLog(fmt, ...) NSLog(fmt, ##__VA_ARGS__)
#else
#define DLog(s, ...) [settings log:[NSString stringWithFormat:s, ##__VA_ARGS__]]
#endif

#endif
