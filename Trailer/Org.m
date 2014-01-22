
@implementation Org

@dynamic avatarUrl;
@dynamic login;

+(Org*)orgWithInfo:(NSDictionary*)info moc:(NSManagedObjectContext*)moc
{
	Org *o = [DataItem itemWithInfo:info type:@"Org" moc:moc];
	o.login = [info ofk:@"login"];
	o.avatarUrl = [info ofk:@"avatar_url"];
	return o;
}

@end
