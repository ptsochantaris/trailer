
#include "Parse8601.h"

// Single-purpose derivation from the excellent SAMAdditions:
// https://github.com/soffes/SAMCategories/blob/master/SAMCategories/NSDate%2BSAMAdditions.m

NSDate *parseGH8601(NSString *iso8601) {

	if(iso8601.length != 20) {
		return NULL;
	}

	char newStr[25] = "                   +0000";
	strncpy(newStr, [iso8601 cStringUsingEncoding:NSUTF8StringEncoding], 19);

	struct tm tm;
	strptime(newStr, "%FT%T%z", &tm);
	time_t t = mktime(&tm);

	return [NSDate dateWithTimeIntervalSince1970:t];
}
