
@implementation NSDictionary (NSDictionary_OFK)

- (id)ofk:(id)key
{
    id o = self[key];
    if([o isKindOfClass:[NSNull class]])
        return nil;
    return o;
}

@end
