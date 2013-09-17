//
// SBModel.m
//  SBData
//
//  Created by Samuel Sutch on 2/14/13.
//  Copyright (c) Steamboat Labs. All rights reserved.
//

#import "SBModel.h"
#import <FMDB/FMDatabaseQueue.h>
#import "SBModel_SBModelPrivate.h"


@implementation SBModel
{
    NSMutableDictionary *_data;
}

+ (SBModelMeta *)meta
{
    id meta = objc_getAssociatedObject(self, "sharedMeta");
    if (!meta) {
        meta = [[SBModelMeta alloc] initWithModelClass:self];
        objc_setAssociatedObject(self, "sharedMeta", meta, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return meta;
}

+ (SBModelMeta *)unsafeMeta
{
    id meta = objc_getAssociatedObject(self, "sharedUnsafeMeta");
    if (!meta) {
        meta = [[SBModelMeta alloc] initWithModelClass:self];
        [meta setUnsafe:YES];
        objc_setAssociatedObject(self, "sharedUnsafeMeta", meta, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return meta;
}

NSMutableArray *_registeredSubclasses;

+ (void)registerModel:(Class)klass
{
    if (!_registeredSubclasses) {
        _registeredSubclasses = [NSMutableArray new];
    }
    [_registeredSubclasses addObject:klass];
}

//
// methods to be implemented by subclasses -----------------------------------------------------------------------------
//

+ (NSArray *)indexes
{
    return @[ ];
}

+ (NSString *)tableName
{
    // name must be implemented by subclasses
    NSString *reason = [NSString stringWithFormat:@"+[%@ name] must be implemented on class and don't call super.",
                        NSStringFromClass(self)];
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:reason userInfo:nil];
}

- (void)willSave
{
    // implement it yo
}

- (void)willReload
{
    // implement it yo
}

//
// key-value coding ----------------------------------------------------------------------------------------------------
//
void setValue(id self, SEL _cmd, id value) {
    NSDictionary *setterMap = objc_getAssociatedObject([self class], "setterToPropertyNameMap");
    NSString *key = [setterMap objectForKey:NSStringFromSelector(_cmd)];
    [self setValue:value forKey:key];
}

id getValue(id self, SEL _cmd) {
    return [self valueForKey:NSStringFromSelector(_cmd)];
}

+ (BOOL)resolveInstanceMethod:(SEL)sel
{
    if ([super resolveInstanceMethod:sel]) {
        return YES;
    }
    NSString *selName = NSStringFromSelector(sel);
    NSSet *setters = objc_getAssociatedObject(self, "dynamicSetters");
    if ([[selName substringToIndex:3] isEqualToString:@"set"] && [setters containsObject:selName]) {
        class_addMethod(self, sel, (IMP)setValue, "v@:@");
        return YES;
    }
    NSSet *getters = objc_getAssociatedObject(self, "dynamicGetters");
    if ([getters containsObject:selName]) {
        class_addMethod(self, sel, (IMP)getValue, "@@:");
        return YES;
    }
    return NO;
}

+ (Class)classForPropertyName:(NSString *)propName
{
    NSDictionary *d = objc_getAssociatedObject(self, "propertyTypeMap");
    if (d) {
        NSString *className = d[propName];
        if (className) {
            return NSClassFromString(className);
        }
    }
    return nil;
}

+ (void)initialize
{
    [super initialize];
    // preform some ahead-of-time computation on dynamic method implementations and such
    NSDictionary *props = [NSObject propertiesForClass:[self class] traversingParentsToClass:[SBModel class]];
    NSMutableSet *setters = [NSMutableSet set];
    NSMutableSet *getters = [NSMutableSet set];
    NSMutableDictionary *setterToPropertyName = [NSMutableDictionary dictionaryWithCapacity:setters.count];
    for (NSString *propName in props) {
        NSString *capitalized = [[[propName substringToIndex:1] capitalizedString] stringByAppendingString:[propName substringFromIndex:1]];
        NSString *setterName = [NSString stringWithFormat:@"set%@:", capitalized];
        [setters addObject:setterName];
        [getters addObject:propName];
        [setterToPropertyName setObject:propName forKey:setterName];
    }
    objc_setAssociatedObject(self, "propertyTypeMap", props, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, "dynamicSetters", setters, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, "dynamicGetters", getters, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, "setterToPropertyNameMap", setterToPropertyName, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (id)valueForKey:(NSString *)key
{
    return _data[key];
}

- (void)setValue:(id)value forKey:(NSString *)key
{
    _data[key] = value;
}

- (void)setValuesForKeysWithDictionary:(NSDictionary *)keyedValues
{
    for (NSString *key in keyedValues) {
        [self setValue:keyedValues[key] forKey:key];
    }
}

- (void)setValuesForKeysWithDatabaseDictionary:(NSDictionary *)keyedValues // same as setValuesForKeysWithDictionary except it respectsSBField coercion
{
    for (NSString *key in keyedValues) {
        Class propClass = [[self class] classForPropertyName:key];
        id value = keyedValues[key];
        if (propClass && [propClass conformsToProtocol:@protocol(SBField)]) {
            value = [propClass fromDatabase:value];
        }
        [self setValue:value forKey:key];
    }
}

- (NSDictionary *)databaseDictionaryValue
{
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithCapacity:_data.count];
    for (NSString *key in _data) {
        Class propClass = [[self class] classForPropertyName:key];
        id value = _data[key];
        if (propClass && [propClass conformsToProtocol:@protocol(SBField)]) {
            value = [value toDatabase];
        }
        d[key] = value;
    }
    return [d copy];
}

- (void)setKey:(NSString *)key
{
    _key = key;
}

- (void)setNilValueForKey:(NSString *)key
{
    [_data removeObjectForKey:key];
}

//
// public --------------------------------------------------------------------------------------------------------------
//

- (id)init
{
    self = [super init];
    if (self) {
        _data = [NSMutableDictionary new];
    }
    return self;
}

- (NSDictionary *)dictionaryValue
{
    return [_data copy];
}

- (void)save
{
    [[[self class] meta] inTransaction:^(SBModelMeta *meta, BOOL *rollback) {
        [meta save:self];
    }];
}

- (void)reload
{
    [[[self class] meta] inDeferredTransaction:^(SBModelMeta *meta, BOOL *rollback) {
        [meta reload:self];
    }];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %@>", NSStringFromClass(self.class), FormatContainer([self dictionaryValue])];
}

- (BOOL)isEqual:(id)object
{
    if (!self.key) {
        return NO; // no way to tell if we don't yet have a key
    }
    if (![object isKindOfClass:[self class]]) {
        return NO;
    }
    if ([[object key] isEqualToString:self.key]) {
        return YES;
    }
    return NO;
}

@end


@implementation SBModelMeta
{
    NSArray *_indexes; // a list of lists containing property names
    NSArray *_indexTableNamesCache;
    Class _modelClass;
    NSString *_name;
    NSString *_databasePath;
}

@synthesize indexes = _indexes;
@synthesize name = _name;
@synthesize modelClass = _modelClass;

- (id)initWithModelClass:(Class)modelClass
{
    self = [super init];
    if (self) {
        _modelClass = modelClass;
        _indexes = [(id)modelClass performSelector:@selector(indexes)];
        _name = [(id)modelClass performSelector:@selector(tableName)];
        _indexTableNamesCache = nil;
        
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *docsPath = [paths objectAtIndex:0];
        _databasePath = [docsPath stringByAppendingPathComponent:@"objects.sqlite3"];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone
{
    SBModelMeta *copy = [[self.class alloc] initWithModelClass:_modelClass];
    return copy;
}

+ (void)initDb
{
    for (Class kls in _registeredSubclasses) {
        [[kls meta] initDb];
    }
}

static FMDatabase *_sharedDb;
static dispatch_queue_t _sharedQueue;

- (FMDatabase*)writeDatabase
{
    if (_sharedDb == nil) {
        _sharedDb = [FMDatabase databaseWithPath:_databasePath];
//        _sharedDb.traceExecution = YES;
//        _sharedDb.busyRetryTimeout = 200; // 200 * 10 ms == max 2s
        NSLog(@"sqlite3_threadsafe %d", sqlite3_threadsafe());
        NSLog(@"sqlite3_version %s", sqlite3_version);
        if (![_sharedDb open]) {
            NSLog(@"SBModelMeta could not reopen writing database for path %@", _databasePath);
            _sharedDb = nil;
            return nil;
        }
    }
    return _sharedDb;
}

- (FMDatabase *)readDatabase
{
    return [self writeDatabase];
}

- (dispatch_queue_t)writeDatabaseQueue
{
    if (!_sharedQueue) {
        _sharedQueue = dispatch_queue_create([@"ctmodel.database-queue" UTF8String], NULL);
    }
    return _sharedQueue;
}

- (dispatch_queue_t)readDatabaseQueue
{
    return [self writeDatabaseQueue];
}

- (void)inDatabase:(void (^)(FMDatabase *db))block
{
    void (^inner)(void) = ^() {
        FMDatabase *db = [self writeDatabase];
        block(db);
        
        if ([db hasOpenResultSets]) {
            NSLog(@"Warning: there is at least one open result set around after performing SBModelMeta inDatabase:]");
            [db closeOpenResultSets];
        }
    };
    if (self.unsafe) {
        inner();
    } else {
        dispatch_sync([self readDatabaseQueue], inner);
    }
}

- (void)beginTransaction:(BOOL)useDeferred withBlock:(void (^)(SBModelMeta *meta, BOOL *rollback))block
{
    void (^inner)(void) = ^() {
        BOOL shouldRollback = NO;
        FMDatabase *db = [self writeDatabase];
        
        if (useDeferred) {
            [db beginDeferredTransaction];
        } else {
            [db beginTransaction];
        }
        
        block(self, &shouldRollback);
        
        if (shouldRollback) {
            [db rollback];
        } else {
            [db commit];
        }
    };
    if (self.unsafe) {
        inner();
    } else {
        dispatch_sync([self writeDatabaseQueue], inner);
    }
}

- (void)inDeferredTransaction:(void (^)(SBModelMeta *meta, BOOL *rollback))block
{
    [self beginTransaction:YES withBlock:block];
}

- (void)inTransaction:(void (^)(SBModelMeta *meta, BOOL *rollback))block
{
    [self beginTransaction:NO withBlock:block];
}

- (NSArray *)_getIndexTableNames
{
    if (_indexTableNamesCache == nil) {
        NSMutableArray *tmp = [NSMutableArray array];
        for (NSArray *idx in _indexes) {
            [tmp addObject:[NSString stringWithFormat:@"%@_%@", _name, [idx componentsJoinedByString:@"_"]]];
        }
        _indexTableNamesCache = [tmp copy];
    }
    return _indexTableNamesCache;
}

- (void)initDb
{
    [self inTransaction:^(SBModelMeta *meta, BOOL *rollback) {
        // create the blob table and its index
        FMDatabase *db = [meta writeDatabase];
        NSString *stmt = [NSString stringWithFormat:
                          @"CREATE TABLE IF NOT EXISTS %@ ("
                          "id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, "
                          "%@ VARCHAR(36) NOT NULL, "
                          "data BLOB NOT NULL)", _name, PRIVATE_UUID_KEY];
        if (![db executeUpdate:stmt]) {
            NSLog(@"error creating table: %@", [db lastError]);
        }
        LogStmt(@"%@", stmt);
        
        stmt = [NSString stringWithFormat:@"CREATE UNIQUE INDEX IF NOT EXISTS %@ on %@ (%@ ASC)",
                [NSString stringWithFormat:@"%@_%@_index", _name, PRIVATE_UUID_KEY], _name, PRIVATE_UUID_KEY];
        if (![db executeUpdate:stmt]) {
            NSLog(@"error creating index: %@", [db lastError]);
        }
        LogStmt(@"%@", stmt);
        
        for (NSArray *idx in _indexes) {
            // create the index table
            NSString *tableName = [NSString stringWithFormat:@"%@_%@", _name, [idx componentsJoinedByString:@"_"]];
            NSMutableString *mStmt = [[NSMutableString alloc] initWithFormat:@"CREATE TABLE IF NOT EXISTS %@ (%@ VARCHAR(36) NOT NULL", tableName, PRIVATE_UUID_KEY];
            for (NSString *field in idx) {
                NSString *fieldType = @"TEXT";
                Class propClass = [_modelClass classForPropertyName:field];
                if (propClass && [propClass conformsToProtocol:@protocol(SBField)]) {
                    fieldType = [propClass databaseType];
                }
                [mStmt appendFormat:@", %@ %@", field, fieldType];
            }
//            [mStmt appendFormat:@", UNIQUE (%@, %@))", PRIVATE_UUID_KEY, [idx componentsJoinedByString:@", "]];
            [mStmt appendFormat:@", UNIQUE(%@))", PRIVATE_UUID_KEY];
            
            if (![db executeUpdate:mStmt]) {
                NSLog(@"error creating index table: %@", [db lastError]);
            }
            LogStmt(@"%@", mStmt);
            
            // create the index table index
            NSString *fields = [idx componentsJoinedByString:@" ASC, "];
            stmt = [NSString stringWithFormat:@"CREATE INDEX IF NOT EXISTS %@_index ON %@ (%@ ASC)", tableName, tableName, fields];
            if (![db executeUpdate:stmt]) {
                NSLog(@"error creating index on index table: %@", [db lastError]);
            }
            LogStmt(@"%@", stmt);
        }
    }];
}

- (void)save:(SBModel *)model
{
    [model willSave];
    NSDictionary *dict = [model databaseDictionaryValue];
    FMDatabase *db = [self writeDatabase];
    NSError *serializeError = nil;

    NSData *JSON = [dict JSONData];
    if (serializeError) {
        NSLog(@"error serializing json data during save: %@", serializeError);
    }
    if (model.key == nil) {
        // no key yet so generate a uuid and set it
        [model setKey:[[NSUUID UUID] UUIDString]];
        
        NSString *stmt = [NSString stringWithFormat:@"INSERT INTO %@ (%@, data) VALUES (?, ?)", _name, PRIVATE_UUID_KEY];
        if (![db executeUpdate:stmt withArgumentsInArray:@[ model.key, JSON ]]) {
            NSLog(@"error inserting: %@", [db lastError]);
        }
        LogStmt(@"%@", stmt);
    } else {
        NSString *stmt = [NSString stringWithFormat:@"UPDATE %@ SET data = ? WHERE %@ = ?", _name, PRIVATE_UUID_KEY];
        if (![db executeUpdate:stmt withArgumentsInArray:@[ JSON, model.key ]]) {
            NSLog(@"error updating: %@", [db lastError]);
        }
        LogStmt(@"%@", stmt);
    }
    // update indexes
    NSArray *tableNames = [self _getIndexTableNames];
    for (NSUInteger i = 0; i < _indexes.count; i++) {
        [self _populateIndex:tableNames[i] fieldNames:_indexes[i] key:model.key values:dict];
    }
}

- (void)_populateIndex:(NSString *)tableName fieldNames:(NSArray *)fieldNames key:(NSString *)key values:(NSDictionary *)dict
{
    NSMutableArray *values = [NSMutableArray arrayWithObject:key];
    for (NSString *fieldName in fieldNames) {
        if (dict[fieldName] == nil) {
            [values addObject:@"__NULL__"];
        } else {
            [values addObject:dict[fieldName]];
        }
    }
    NSMutableString *questionMarks = [NSMutableString string];
    NSMutableIndexSet *ignoreNullIndexes = [NSMutableIndexSet indexSet];
    for (NSUInteger i = 0; i < values.count; i++) {
        if ([values[i] isEqual:@"__NULL__"]) {
            [questionMarks appendString:@"NULL, "];
            //NSLog(@"Inserting NULL into index %@. The corresponding row will not be available when selected using this index.", fieldNames);
            [ignoreNullIndexes addIndex:i];
        } else {
            [questionMarks appendString:@"?, "];
        }
    }
    [values removeObjectsAtIndexes:ignoreNullIndexes];
    NSString *stmt = [NSString stringWithFormat:@"INSERT OR REPLACE INTO %@ (%@, %@) VALUES (%@)", tableName, PRIVATE_UUID_KEY,
                      [fieldNames componentsJoinedByString:@", "],
                      [questionMarks substringToIndex:questionMarks.length -2]];
    if (![[self writeDatabase] executeUpdate:stmt withArgumentsInArray:values]) {
        NSLog(@"error updating index: %@", [[self writeDatabase] lastError]);
    }
}

- (void)reload:(SBModel *)obj
{
    if (!obj.key) {
        return; // can not reload the object if it does not exist
    }
    FMDatabase *db = [self readDatabase];
    NSString *query = [NSString stringWithFormat:@"SELECT data FROM %@ WHERE %@ = ?", _name, PRIVATE_UUID_KEY];
    LogStmt(query);
    FMResultSet *res = [db executeQuery:query withArgumentsInArray:@[ obj.key ]];
    while ([res next]) {
        NSDictionary *data = [[res dataForColumnIndex:0] objectFromJSONData];
        if (data) {
            [obj willReload];
            [obj setValuesForKeysWithDatabaseDictionary:data];
        }
        break;
    }
}

// search the database and returns a list of model objects
//
//      - `paramters` is a mapping of parameter=>values
//
//         you may include any number of valid parameters to filter against, only those that match will be included in the results
//
//         supported formats:
//              @{ @"paramterName": @"string value" } - will return only results that have the matching paramter
//              @{ @"parameterName: [NSSet setWithObjects:@"string value 1", @"string value 2", nil] - will return only results that have the the matching parameter in the set of options
//
//      - `orderBy` is an array of parameters by which to sort
//
//        for example @[ @"lastName", @"firstName" ] make the returned array sorted by first the @"firstName" property (alphabetically) and then the @"lastName" property (alphabetically)
//
//        currently supported parameter types to sort on:
//              - NSString
//              - NSNumber
//              - Adding NSDate in the future

- (SBModelResultSet *)findWithProperties:(NSDictionary *)properties orderBy:(NSArray *)orderBy sorting:(SBModelSorting)sort
{
    SBModelQueryBuilder *builder = [[[self queryBuilder] orderByProperties:orderBy] sort:sort];
    for (id k in properties) {
        if ([properties[k] isKindOfClass:[NSSet class]]) {
            [builder property:k isContainedWithin:properties[k]];
        } else {
            [builder property:k isEqualTo:properties[k]];
        }
    }
    SBModelQuery *query = [builder query];
    return [query results];
}

- (id)findOne:(NSDictionary *)properties
{
    SBModelResultSet *res = [self findWithProperties:properties orderBy:@[ @"key" ] sorting:SBModelAscending];
    if (res.count) {
        return [[res allObjects] lastObject];
    }
    return nil;
}

- (id)findByKey:(NSString *)key
{
    if (key == nil) {
        return nil;
    }
    return [self findOne:@{ @"key": key }];
}

- (SBModelQueryBuilder *)queryBuilder
{
    return [[SBModelQueryBuilder alloc] initWithMeta:self];
}

@end


@implementation SBModelResultSet
{
    NSUInteger _pageSize;
    SBModelQuery *_query;
    NSMutableArray *_pages;
    NSUInteger _count;
    BOOL _firstLoad; // a flag used to defer calling -reload for the first time until its absolutely needed, this allows for late-creation of the query object
}

- (void)_loadIfFirst
{
    if (!_firstLoad) {
        [self reload];
        _firstLoad = YES;
    }
}

- (id)initWithQuery:(SBModelQuery *)query
{
    self = [super init];
    if (self) {
        _query = query;
        _pageSize = 50;
        _firstLoad = NO;
        
//        [self reload];
    }
    return self;
}

- (void)setQuery:(SBModelQuery *)query
{
    _query = query;
    [self reload];
}

- (void)reload
{
    _count = [[self query] count];
    NSUInteger npages = (_count / _pageSize + 1);
    NSMutableArray *pages = [NSMutableArray arrayWithCapacity:npages];
    for (NSUInteger i = 0; i < npages; i++) {
        [pages addObject:@[ [NSMutableArray arrayWithCapacity:_pageSize], [NSNumber numberWithBool:NO] ]];
    }
    _pages = pages;
}

- (NSUInteger)count
{
    [self _loadIfFirst];
    return _count;
}

- (id)first
{
    if ([self count]) {
        return [self objectAtIndex:0];
    }
    return nil;
}

- (id)objectAtIndex:(NSUInteger)idx
{
    [self _loadIfFirst];
    NSParameterAssert(idx < [self count]);
    
    NSUInteger page = [self _pageForIndex:idx];
    if (![self _hasPage:page]) {
        [self _fetchPage:page];
    }
    return _pages[page][0][idx % _pageSize];
}

- (NSArray *)allObjects
{
    [self _loadIfFirst];
    for (NSUInteger i = 0; i < _pages.count; i++) {
        if (![self _hasPage:i]) {
            [self _fetchPage:i];
        }
    }
    NSMutableArray *ret = [NSMutableArray arrayWithCapacity:_pages.count * _pageSize];
    for (NSArray *page in _pages) {
        [ret addObjectsFromArray:page[0]];
    }
    return [ret copy];
}

- (NSArray *)fetchedObjects
{
    [self _loadIfFirst];
    NSMutableArray *ret = [NSMutableArray arrayWithCapacity:_pages.count * _pageSize];
    for (NSArray *page in _pages) {
        [ret addObjectsFromArray:page[0]];
    }
    return [ret copy];
}

- (BOOL)_hasPage:(NSUInteger)pageNum
{
    [self _loadIfFirst];
    return [_pages[pageNum][1] boolValue];
}

- (NSUInteger)_pageForIndex:(NSUInteger)idx
{
    return idx / _pageSize;
}

- (void)_fetchPage:(NSUInteger)pageNum // refetches the page whether or not its already been fetched
{
    [self _loadIfFirst];
    NSParameterAssert(pageNum < _pages.count);
    NSArray *pg = [[self query] fetchOffset:pageNum*_pageSize count:_pageSize];
    _pages[pageNum] = @[ pg, [NSNumber numberWithBool:YES] ];
}

@end
