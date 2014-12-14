
@import Cocoa;

#define STATUSITEM_PADDING 1.0
#define TOP_HEADER_HEIGHT 28.0
#define AVATAR_SIZE 26.0
#define LEFTPADDING 44.0
#define TITLE_HEIGHT 42
#define BASE_BADGE_SIZE 21.0
#define SMALL_BADGE_SIZE 14.0
#define MENU_WIDTH 500.0

#define COLOR_CLASS NSColor
#define IMAGE_CLASS NSImage
#define FONT_CLASS NSFont
#define MAKECOLOR(R,G,B,A) [COLOR_CLASS colorWithSRGBRed:R green:G blue:B alpha:A]

#define CACHE_MEMORY 1024*1024*4
#define CACHE_DISK 1024*1024*128

#import "GlobalsObjC.h"

#import "OSX_AppDelegate.h"
extern OSX_AppDelegate *app;
