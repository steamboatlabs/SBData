//
// SBModelQuery.m
//  SBData
//
//  Created by Samuel Sutch on 3/29/13.
//  Copyright (c) Steamboat Labs. All rights reserved.
//

#import "SBModelQuery.h"
#import "SBModel.h"
#import "SBModelQueryTerm.h"
#import "SBModel_SBModelPrivate.h"

const NSTimeInterval timeSince(NSDate *since) {
    return [since timeIntervalSinceNow] * -1000.0;
}

//
// QUERY ---------------------------------------------------------------------------------------------------------------
//

@interface SBModelQuery ()


- (void)_genQuery;
//- (void)populateWithParameters:(NSDictionary *)params orderBy:(NSArray *)orderBy sort:(SBModelSorting)sort decorator:(id(^)(SBModel *))dec;
- (void)populateWithTerms:(NSSet *)terms orderBy:(NSArray *)orderBy sort:(SBModelSorting)sort decorator:(id(^)(SBModel *))dec;

// helper to determine which is most satisfying to the given prop names
//- (NSArray *)_getLargestIndex:(NSArray *)propnames;
- (NSArray *)_getLargestIndex:(NSSet *)propnames;

- (NSString *)_quotedString:(NSString *)str;
//- (NSDictionary *)_whereClauseForColumn:(NSString *)colName term:(id<SBModelQueryTerm>)value;
- (NSDictionary *)_orderByClauseForColumns:(NSArray *)columns sort:(SBModelSorting)sortOrder;
- (NSString *)_queryForFields:(NSArray *)fields includeSort:(BOOL)sortClause; // manualFields:(NSDictionary **)manual queryParams:(NSDictionary **)params;

@property (nonatomic) BOOL dirty;
@property (nonatomic, readonly) NSString *query;
@property (nonatomic, readonly) NSDictionary *queryParameters;
@property (nonatomic, readonly) NSDictionary *manualSearchFields;

@end


@implementation SBModelQuery
{
    SBModelMeta *_meta;
    NSString *_query;
//    NSDictionary *_manualSearchFields;
//    NSDictionary *_queryParameters;
    
//    NSDictionary *_parameters;
    NSSet *_queryTerms;
    NSArray *_orderBy;
    SBModelSorting _sortOrder;
}

- (id)initWithMeta:(SBModelMeta *)meta
{
    self = [super init];
    if (self) {
        _meta = meta;
        _dirty = NO;
        _sortOrder = SBModelAscending;
    }
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %@>", NSStringFromClass([self class]), self.query];
}

//- (void)populateWithParameters:(NSDictionary *)params orderBy:(NSArray *)orderBy sort:(SBModelSorting)sort decorator:(id(^)(SBModel *))dec
- (void)populateWithTerms:(NSSet *)terms orderBy:(NSArray *)orderBy sort:(SBModelSorting)sort decorator:(id(^)(SBModel *))dec
{
    self.dirty = YES;
//    _parameters = params;
    _queryTerms = terms;
    _orderBy = orderBy;
    _sortOrder = sort;
    _decorator = dec;
}

- (void)setDirty:(BOOL)dirty
{
    if (dirty) {
        _query = nil;
//        _queryParameters = nil;
//        _manualSearchFields = nil;
    }
    _dirty = dirty;
}

- (NSString *)query
{
    [self _genQuery];
    return _query;
}

//- (NSDictionary *)queryParameters
//{
//    [self _genQuery];
//    return _queryParameters;
//}
//
//- (NSDictionary *)manualSearchFields
//{
//    [self _genQuery];
//    return _manualSearchFields;
//}

- (SBModelResultSet *)results
{
    return [[SBModelResultSet alloc] initWithQuery:self];
}

// returns a list of the columns that will be needed for all query terms in _queryTerms
- (NSSet *)_getColumnsFromQueryTerms
{
    NSMutableSet *ret = [NSMutableSet setWithCapacity:_queryTerms.count];
    for (NSObject<SBModelQueryTerm> *term in _queryTerms) {
        for (id p in term.propNames) {
            [ret addObject:p];
        }
    }
    return ret;
}

- (NSString *)_getKeyFromQueryTerms
{
    NSSet *needle = [NSSet setWithObject:@"key"];
    for (NSObject<SBModelQueryTerm> *term in _queryTerms) {
        if ([[term propNames] isEqualToSet:needle]) {
            return term.value;
        }
    }
    return @"";
}

// determine the largest available index for all the prop names
- (NSArray *)_getLargestIndex:(NSSet *)propnames
{
//    NSSet *fieldSet = [NSSet setWithArray:propnames];
    NSMutableArray *indexes = [NSMutableArray array];
    for (NSArray *idx in _meta.indexes) {
        [indexes addObject:@[ [NSMutableSet setWithArray:idx], idx ]];
    }
    NSMutableArray *coverage = [NSMutableArray array];
    for (NSArray *index in indexes) {
        //        if (![index[0] isSubsetOfSet:fieldSet]) {
        if (![propnames isSubsetOfSet:index[0]]) { // if index[0] does not contain at least as many similar elements to fieldSet
            continue;
        }
        NSMutableSet *mFieldSet = [propnames mutableCopy];
        for (NSString *field in index[0]) {
            [mFieldSet removeObject:field];
        }
        [coverage addObject:@[ @(mFieldSet.count), index[1] ]];
    }
    if (!coverage.count) {
        return  @[ ];
    }
    [coverage sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        return [obj1[0] compare:obj2[0]];
    }];
    
    return coverage[0][1];
}

// given the columns being queried on, determine the index to use
- (NSArray *)_indexForColumns:(NSSet *)columns
{
    NSArray *index;
    if (!columns.count) {
        index = @[];
    } else if ([columns containsObject:@"key"]) {
        index = @[ @"key" ];
    } else {
        index = [self _getLargestIndex:columns];
    }
    return index;
}

// uses sqlite sqlite `mprintf` function to turn a string into a literal safe to insert directly into a query string
- (NSString *)_quotedString:(NSString *)str
{
    char *theEscapedValue = sqlite3_mprintf("'%q'", [str UTF8String]);
    NSString *escapedValue = [NSString stringWithUTF8String:(const char *)theEscapedValue];
    sqlite3_free(theEscapedValue);
    return escapedValue;
}

// takes a mapping ot COLUMN => VALUE and turns it into a WHERE clause which an then be inserted directly into the query
// the return value is a mapping of:
//      @"text": STRING VALUE - the part to be inserted into the query
//      @"parameters": PARAMETER DICTINOARY - the parameters to be provided to this part of the query
//- (NSDictionary *)_whereClauseForColumn:(NSString *)colName term:(id<SBModelQueryTerm>)value
//{
    //    if ([value isKindOfClass:[NSSet class]]) {
    //        NSMutableArray *escapedValues = [NSMutableArray arrayWithCapacity:[value count]];
    //        NSArray *arrayValue = [value allObjects];
    //        for (id el in arrayValue) {
    //            if (![el isKindOfClass:[NSString class]]) {
    //                NSLog(@"Tried to execute an IN() search but all elements of the set were not strings");
    //                goto unknown_type;
    //            }
    //            [escapedValues addObject:[self _quotedString:el]];
    //        }
    //        return @{ @"text": [NSString stringWithFormat:@"%@ IN(%@)", colName, [escapedValues componentsJoinedByString:@", "]],
    //                  @"paraemters": @{ } };
    //    }
    //
    //unknown_type:
    //    return @{ @"text": [NSString stringWithFormat:@"%@ = :%@", colName, colName], @"parameters": @{ colName: value } };
//    return @{ @"text": [value render], @"parameters": @{ } };
//}

// takes a list of columns and turns it into a order by clause for a query
// in order to order adding a join may be required
// the return value is a mapping of:
//      @"text": STRING VALUE - the actual ORDER BY... clause
//      @"join": STRING VALUE - the INNER JOIN if required to support the order - otherwise empty string
//      @"index": ARRAY - the index used to ORDER BY - if required, can be used to dedupe joins
- (NSDictionary *)_orderByClauseForColumns:(NSArray *)columns sort:(SBModelSorting)sortOrder
{
    NSDictionary *emptyOrderBy = @{ @"text": @"", @"join": @"", @"index": @[ ] };
    NSString *sort = sortOrder == SBModelAscending ? @"ASC" : @"DESC";
    NSDictionary *ret = nil;
    if (columns == nil) {
        ret = emptyOrderBy;
    }
    // sorting by key or id has a default behavior
    if ([columns isEqualToArray:@[@"key"]] || [columns isEqualToArray:@[@"id"]]) {
        return @{ @"text": [NSString stringWithFormat:@"ORDER BY x.%@ %@ ", PRIVATE_UUID_KEY, sort], @"join": @"", @"index": @[ ] };
    }
    // otherwise search for an index that can satisfy all of the columns
    NSArray *index = [self _getLargestIndex:[NSSet setWithArray:columns]];
    for (NSString *col in columns) {
        if (![index containsObject:col]) {
            // if the index can not satisfy all of the columns we can't relibaly sort on it
            ret = emptyOrderBy;
            NSLog(@"Tried to order by (%@) but couldn't because there is no index that indexes all of those columns.",
                  [columns componentsJoinedByString:@","]);
            break;
        }
    }
    if (ret == emptyOrderBy) {
        return emptyOrderBy;
    }
    NSString *order = [NSString stringWithFormat:@"ORDER BY s.%@ %@", [columns componentsJoinedByString:@", s."], sort];
    NSString *joinText = [NSString stringWithFormat:@"INNER JOIN %@_%@ s ON x.%@ = s.%@", _meta.name, [index componentsJoinedByString:@"_"],
                          PRIVATE_UUID_KEY, PRIVATE_UUID_KEY];
    return @{ @"text": order, @"join": joinText, @"index": index };
}

- (NSString *)_queryForFields:(NSArray *)fields includeSort:(BOOL)sortClause //manualFields:(NSDictionary **)manual queryParams:(NSDictionary **)params
{
//    NSArray *index;
    NSString *stmt;
//    NSMutableDictionary *manualSearchFields = [NSMutableDictionary dictionary]; //[_parameters mutableCopy];
//    NSDictionary *queryDict;
    
    NSSet *columns = [self _getColumnsFromQueryTerms];
//    NSLog(@"columns: %@", columns);
    NSArray *index = [self _indexForColumns:columns];
    
//    if (_parameters == nil) {
//        _parameters = @{ };
//        index = @[ ];
//    } else if (_parameters[@"key"] != nil) {
//        index = @[ @"key" ];
//    } else {
//        index = [self _getLargestIndex:[_parameters allKeys]];
//    }

    // determine which index to use for sorting - if excluding ordering just get an empty order by back
    NSDictionary *order = sortClause ? [self _orderByClauseForColumns:_orderBy sort:_sortOrder] : [self _orderByClauseForColumns:nil sort:SBModelAscending];
    
    NSString *fieldsStr = @"";
    if ([fields isEqualToArray:@[ @"COUNT(*)" ]]) { // special case for when we want a count - currently only COUNT(*) is supported
        fieldsStr = fields[0];
    } else {
        fieldsStr = [NSString stringWithFormat:@"x.%@", [fields componentsJoinedByString:@", x."]];
    }
    
    if (!index.count) {
        stmt = [NSString stringWithFormat:@"SELECT %@ FROM %@ x %@ %@", fieldsStr, _meta.name, order[@"join"], order[@"text"]];
//        queryDict = @{ };
    }  else if ([index isEqualToArray:@[ @"key" ]]) {
        stmt = [NSString stringWithFormat:@"SELECT %@ FROM %@ x %@ WHERE x.%@ = %@ %@", fieldsStr, _meta.name, order[@"join"],
                PRIVATE_UUID_KEY, [self _quotedString:[self _getKeyFromQueryTerms]], order[@"text"]];
//        queryDict = @{ @"key": [(id<SBModelQueryTerm>)_parameters[@"key"][0] value] };
//        [manualSearchFields removeAllObjects];
    } else {
        NSMutableArray *whereClauses = [NSMutableArray array];
//        NSMutableDictionary *queryParamters = [NSMutableDictionary dictionary];
//        for (NSString *indexComponent in index) {
//            for (id<SBModelQueryTerm> term in _parameters[indexComponent]) {
//                NSDictionary *where = [self _whereClauseForColumn:indexComponent term:term];
//                [whereClauses addObject:where[@"text"]];
//                for (NSString *paramKey in where[@"parameters"]) {
//                    [queryParamters setObject:where[@"parameters"][paramKey] forKey:paramKey];
//                }
//            }
//        }
        for (id<SBModelQueryTerm> term in _queryTerms) {
            // ensure that all prop names being examined by this term are available in the index
            for (id prop in [term propNames]) {
                if (![index containsObject:prop]) {
                    goto manual_search;
                }
            }
        db_search:
            [whereClauses addObject:[term renderWithNamespace:@"y"]];
            continue;
        manual_search:
            NSLog(@"UNABLE TO QUERY TERM: %@ - MISSING INDEX", term);
            continue; // TODO: implement manual search
        }
        stmt = [NSString stringWithFormat:@"SELECT %@ FROM %@ x INNER JOIN %@_%@ y ON x.%@ = y.%@ %@ WHERE %@ %@",
                fieldsStr, _meta.name, _meta.name, [index componentsJoinedByString:@"_"], PRIVATE_UUID_KEY, PRIVATE_UUID_KEY,
                order[@"join"], [whereClauses componentsJoinedByString:@" AND "], order[@"text"]];
//        queryDict = [queryParamters copy];
//        for (NSString *k in index) {
//            [manualSearchFields removeObjectForKey:k];
//        }
    }
//    if (manual && *manual == nil) {
//        *manual = manualSearchFields;
//    }
//    *params = queryDict;
    return stmt;
}

- (void)_genQuery
{
    if (_query != nil) { // && _queryParameters != nil && _manualSearchFields != nil) {
        return;
    }
//    NSDictionary *queryParams = nil;
//    NSDictionary *manualFields = nil;
    _query = [self _queryForFields:@[ @"id", PRIVATE_UUID_KEY, @"data" ] includeSort:YES]; //manualFields:&manualFields queryParams:&queryParams];
//    _queryParameters = queryParams;
//    _manualSearchFields = manualFields;
}

- (NSArray *)fetchOffset:(NSInteger)offset count:(NSInteger)count // not guaranteed to return `count` number of items - manual filtering may be required
{
    NSParameterAssert((offset == -1 && count) || (offset != -1 && count != -1) || (offset == -1 && count == -1)); // you can provide count, count and offset, or neither
    NSDate *start = [NSDate date];
    
    // add LIMIT/OFFSET clause
    NSMutableString *query = [NSMutableString stringWithString:self.query];
    if (count > 0) {
        [query appendFormat:@" LIMIT %d", count];
    }
    if (offset > -1 && count > 0) { // OFFSET is only available when paired with LIMIT
        [query appendFormat:@" OFFSET %d", offset];
    }
    __block NSMutableArray *ret = [NSMutableArray array];
    [_meta inDatabase:^(FMDatabase *db) {
        FMResultSet *results = [db executeQuery:query withParameterDictionary:self.queryParameters];
        if (results == nil) {
            NSLog(@"query string: %@", self.query);
            NSLog(@"ERROR QUERYING: %@", [db lastError]);
            return;
        }
        
        while ([results next]) {
            NSDictionary *data = [[results dataForColumnIndex:2] objectFromJSONData];
//            if (_manualSearchFields.count) {
//                for (NSString *paramKey in _manualSearchFields) {
//                    if (![data[paramKey] isEqual:_parameters[paramKey]]) { // TODO: match columns other than strings (eg NSSet)
//                        goto ignore_row;
//                    }
//                    goto keep_row;
//                }
//            ignore_row:
//                continue;
//            }
            
        keep_row:;
            NSString *key = [results stringForColumnIndex:1];
            SBModel *model = [[_meta.modelClass alloc] init];
            if (_decorator) {
                model = _decorator(model);
            }
            //[model setValuesForKeysWithDictionary:data];
            [model setValuesForKeysWithDatabaseDictionary:data];
            [model setKey:key];
            [ret addObject:model];
        }
        [results close];
    }];
    LogStmt(@"executed query: %@", query);
//    LogStmt(@"manual search fields %@", [[_manualSearchFields allKeys] componentsJoinedByString:@", "]);
    LogStmt(@"total returned: %d", [ret count]);
    LogStmt(@"total time: %f", timeSince(start));
    return ret;
}

- (NSUInteger)count
{
    if (self.manualSearchFields.count) {
        NSLog(@"Can not count the query because there are missing indexes: %@", FormatContainer(self.manualSearchFields.allKeys));
        return 0;
    }
    NSDate *start = [NSDate date];
//    NSDictionary *queryParams = nil;
    NSString *query = [self _queryForFields:@[ @"COUNT(*)" ] includeSort:YES]; // manualFields:nil queryParams:&queryParams];
    __block NSUInteger r = 0;
    [_meta inDatabase:^(FMDatabase *db) {
//        FMResultSet *result = [db executeQuery:query withParameterDictionary:queryParams];
        FMResultSet *result = [db executeQuery:query];
        if (result == nil) {
            NSLog(@"query string: %@", self.query);
            NSLog(@"ERROR QUERYING: %@", [db lastError]);
            return;
        }
        [result next];
        r = [result intForColumnIndex:0];
        [result close];
    }];
    LogStmt(@"executed count: %@", query);
    LogStmt(@"total time: %f", timeSince(start));
    return r;
}

@end

//
// QUERY BUILDER -------------------------------------------------------------------------------------------------------
//

@implementation SBModelQueryBuilder
{
//    NSMutableArray *_equalTo;
//    NSMutableArray *_notEqualTo;
//    NSMutableArray *_containedWithin;
    NSMutableArray *_terms;
    SBModelSorting _sort;
    NSArray *_orderBy;
    SBModelMeta *_meta;
    id (^_resultDecorator)(SBModel *);
}

- (id)initWithMeta:(SBModelMeta *)meta
{
    self = [super init];
    if (self) {
        _meta = meta;
//        _equalTo = [NSMutableArray array];
//        _notEqualTo = [NSMutableArray array];
//        _containedWithin = [NSMutableArray array];
        _terms = [NSMutableArray array];
        _sort = SBModelAscending;
        _orderBy = @[ @"key" ];
    }
    return self;
}

- (SBModelQueryBuilder *)property:(NSString *)propName isEqualTo:(id)obj
{
    [_terms addObject:[[SBModelQueryTermEquals alloc] initWithPropName:propName value:obj]];
    return self;
}

- (SBModelQueryBuilder *)property:(NSString *)propName isNotEqualTo:(id)obj
{
    [_terms addObject:[[SBModelQueryTermNotEquals alloc] initWithPropName:propName value:obj]];
    return self;
}

- (SBModelQueryBuilder *)property:(NSString *)propName isContainedWithin:(NSSet *)set
{
    [_terms addObject:[[SBModelQueryTermContainedWithin alloc] initWithPropName:propName value:set]];
    return self;
}

- (SBModelQueryBuilder *)properties:(NSArray *)propNames areNotEqualTo:(NSArray *)values
{
    NSParameterAssert(propNames.count == values.count);
    NSMutableArray *contained = [NSMutableArray arrayWithCapacity:propNames.count];
    for (int i = 0; i < propNames.count; i++) {
        [contained addObject:[[SBModelQueryTermEquals alloc] initWithPropName:propNames[i] value:values[i]]];
    }
    [_terms addObject:[[SBModelQueryTermNot alloc] initWithQueryTerms:contained]];
    return self;
}

- (SBModelQueryBuilder *)propertyTuple:(NSArray *)propNames isContainedWithinValueTuples:(NSSet *)set
{
    NSMutableArray *options = [NSMutableArray arrayWithCapacity:set.count];
    for (NSArray *tup in set) {
        NSMutableArray *ands = [NSMutableArray arrayWithCapacity:tup.count];
        for (int i = 0; i < propNames.count; i++) {
            [ands addObject:[[SBModelQueryTermEquals alloc] initWithPropName:propNames[i] value:tup[i]]];
        }
        [options addObject:[[SBModelQueryTermAnd alloc] initWithQueryTerms:ands]];
    }
    [_terms addObject:[[SBModelQueryTermOr alloc] initWithQueryTerms:options]];
    return self;
}

- (SBModelQueryBuilder *)propertyTuple:(NSArray *)propNames isNotContainedWithinValueTuples:(NSSet *)set
{
    NSMutableArray *options = [NSMutableArray arrayWithCapacity:set.count];
    for (NSArray *tup in set) {
        NSMutableArray *ands = [NSMutableArray arrayWithCapacity:tup.count];
        for (int i = 0; i < propNames.count; i++) {
            [ands addObject:[[SBModelQueryTermEquals alloc] initWithPropName:propNames[i] value:tup[i]]];
        }
        [options addObject:[[SBModelQueryTermAnd alloc] initWithQueryTerms:ands]];
    }
    [_terms addObject:[[SBModelQueryTermNot alloc] initWithQueryTerms:@[ [[SBModelQueryTermOr alloc] initWithQueryTerms:options]] ]];
    return self;
}

- (SBModelQueryBuilder *)sort:(SBModelSorting)sortOrder
{
    _sort = sortOrder;
    return self;
}

- (SBModelQueryBuilder *)orderByProperties:(NSArray *)orderingProperties
{
    _orderBy = [orderingProperties copy];
    return self;
}

- (SBModelQueryBuilder *)decorateResults:(id (^)(SBModel *))decorator
{
    _resultDecorator = decorator;
    return self;
}

- (SBModelQuery *)query
{
//    NSMutableDictionary *props = [NSMutableDictionary dictionary];
//    void(^setProp)(id, NSUInteger, BOOL *) = ^ (NSArray *obj, NSUInteger idx, BOOL *stop) {
//        if (!props[obj[0]]) {
//            props[obj[0]] = [NSMutableArray array];
//        }
//        [props[obj[0]] addObject:obj[1]];
//    };
//    [_equalTo enumerateObjectsUsingBlock:setProp];
//    [_notEqualTo enumerateObjectsUsingBlock:setProp];
//    [_containedWithin enumerateObjectsUsingBlock:setProp];
    
    SBModelQuery *q = [[SBModelQuery alloc] initWithMeta:_meta];
//    [q populateWithTerms:[NSSet setWithArray:_terms] orderBy:_orderBy sort:_sort decorator:_resultDecorator];
    SBModelQueryTermAnd *qt = [[SBModelQueryTermAnd alloc] initWithQueryTerms:_terms];
    
    [q populateWithTerms:[NSSet setWithObject:qt] orderBy:_orderBy sort:_sort decorator:_resultDecorator];
//    [q populateWithParameters:props orderBy:_orderBy sort:_sort decorator:_resultDecorator];
    
    return q;
}

@end