//
// SBDataObject.m
//  SBData
//
//  Created by Samuel Sutch on 2/11/13.
//  Copyright (c) Steamboat Labs. All rights reserved.
//

#import "SBDataObject.h"
#import <objc/runtime.h>
#import <JSONKit/JSONKit.h>
#import "SBUser.h"
#import "NSDictionaryOfParametersFromURL.h"


@interface SBDataObject ()

- (void)saveWithClient:(AFHTTPClient *)cli success:(SBSuccessBlock)success failure:(SBErrorBlock)failure;

- (void)getRedirectResponse:(NSHTTPURLResponse *)response client:(AFHTTPClient *)cli
                    success:(SBSuccessBlock)success failure:(SBErrorBlock)failure;

// @property (nonatomic)SBSession *session;

+ (NSDictionary *)cachedPropertyToNetworkKeyMapping;
+ (void)_saveBulkObjectsFromNetwork:(id)json session:(SBSession *)session existingKey:(NSString *)existingKey
                            success:(SBSuccessBlock)success;

@end

@implementation SBDataObject

//
// SBModel builtins ----------------------------------------------------------------------------------------------------
//
@dynamic objId;
@dynamic userKey;

+ (NSArray *)indexes { return [[super indexes] arrayByAddingObjectsFromArray:@[ @[ @"objId", @"userKey" ] ]]; }

- (void)willSave
{
    [super willSave];
    if (!self.userKey && self.session.user.key) {
        self.userKey = self.session.user.key;
    }
}

//
// init
//

- (id)initWithSession:(SBSession *)sesh
{
    self = [super init];
    if (self) {
        self.session = sesh;
        self.authorized = YES;
    }
    return self;
}

//- (id)init
//{
//    [[NSException exceptionWithName:NSInternalInconsistencyException
//                             reason:@"-SBDataObject initWithSession:] must be used to createSBDataObject instances"
//                           userInfo:nil] raise];
//    return nil;
//}

+ (void)initialize
{
    [super initialize];
    dispatch_queue_t queue = dispatch_queue_create([[NSString stringWithFormat:@"com.sbdata.models.%@.processing-queue",
                                                     NSStringFromClass(self)] UTF8String], NULL);
    objc_setAssociatedObject(self, "processingQueue", queue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

//
// Serialization -------------------------------------------------------------------------------------------------------
//
+ (NSDictionary *)propertyToNetworkKeyMapping
{
    return @{ @"objId": @"id" };
}

+ (NSDictionary *)cachedPropertyToNetworkKeyMapping
{
    id ret = objc_getAssociatedObject(self, "propertyToNetworkKeyMapping");
    if (ret == nil) {
        ret = [self propertyToNetworkKeyMapping];
        objc_setAssociatedObject(self, "propertyToNetworkKeyMapping", ret, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    return ret;
}

+ (instancetype)findWithNetworkRepresentation:(NSDictionary *)dict session:(SBSession *)session
{
    if (dict[@"id"]) {
        return [[[[[session unsafeQueryBuilderForClass:self] property:@"objId" isEqualTo:dict[@"id"]] query] results] first];
    }
    return nil;
}

+ (instancetype)fromNetworkRepresentation:(NSDictionary *)dict session:(SBSession *)session save:(BOOL)persist
{
    SBDataObject *ret = [self findWithNetworkRepresentation:dict session:session];
    if (!ret) {
        ret = [[self alloc] initWithSession:session];
    }
    [ret setValuesForKeysWithNetworkDictionary:dict];
    if (persist) {
        [[self unsafeMeta] save:ret];
    }
    return (id)ret;
}

- (NSDictionary *)toNetworkRepresentation
{
    NSDictionary *keyMap = [[self class] cachedPropertyToNetworkKeyMapping];
    NSMutableDictionary *ret = [NSMutableDictionary dictionaryWithCapacity:keyMap.count];
    for (NSString *localKey in keyMap) {
        id localValue = [self valueForKey:localKey];
        if (localValue != nil) {
            ret[keyMap[localKey]] = [self valueForKey:localKey];
        }
    }
    return ret;
}

- (void)setValuesForKeysWithNetworkDictionary:(NSDictionary *)keyedValues
{
    NSDictionary *keyMap = [self.class cachedPropertyToNetworkKeyMapping];
    for (NSString *localKey in keyMap) {
        if (keyedValues[keyMap[localKey]]) {
            id val = keyedValues[keyMap[localKey]];
            if ([val isEqual:[NSNull null]]) {
                [self setNilValueForKey:localKey];
            } else {
                [self setValue:val forKey:localKey];
            }
        }
    }
}

//
// HTTP mapping --------------------------------------------------------------------------------------------------------
//

+ (NSString *)bulkPath { return @""; }
- (NSString *)listPath { return [self.class bulkPath]; }
- (NSString *)detailPathSpec { return [[self.class bulkPath] stringByAppendingString:@"/%@"]; }

- (NSString *)path
{
    if (self.objId) {
        return [NSString stringWithFormat:self.detailPathSpec, self.objId];
    }
    return self.listPath;
}

- (AFHTTPClientParameterEncoding)paramterEncoding { return AFJSONParameterEncoding; }

//
// bulk saving ---------------------------------------------------------------------------------------------------------
//

+ (void)_saveBulkObjectsFromNetwork:(id)json session:(SBSession *)session existingKey:(NSString *)existingKey success:(SBSuccessBlock)success
{
//    // get a list of existing IDs
//    NSMutableSet *existing = [NSMutableSet set];
//    for (NSDictionary *dict in json) {
//        [existing addObject:dict[[self cachedPropertyToNetworkKeyMapping][existingKey]]];
//    }
// SBModelResultSet *results = [[self meta] findWithProperties:@{ existingKey: existing, @"userKey": session.user.key }
//                                                        orderBy:@[ existingKey ] sorting:SBModelAscending];
// SBModelResultSet *results = [[[[session queryBuilderForClass:self] property:existingKey isContainedWithin:existing] query] results];
//    NSMutableDictionary *mapping = [NSMutableDictionary dictionaryWithCapacity:results.count];
//    for (NSUInteger i = 0; i < results.count; i ++) {
//// this should not be needed since the results are wrapped
////        [[results objectAtIndex:i] setSession:session];
////        [[results objectAtIndex:i] setAuthorized:YES];
//#pragma clang diagnostic push
//#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
//        mapping[[[results objectAtIndex:i] performSelector:NSSelectorFromString(existingKey)]] = [results objectAtIndex:i];
//#pragma clang diagnostic pop
//    }
    [[self meta] inTransaction:^(SBModelMeta *meta, BOOL *rollback) {
        NSMutableArray *ret = [NSMutableArray array];
        for (NSDictionary *dict in json) {
// SBDataObject *obj = mapping[dict[[self cachedPropertyToNetworkKeyMapping][existingKey]]];
//            if (obj == nil) {
//                obj = [[self alloc] initWithSession:session];
//            }
//            [obj setValuesForKeysWithNetworkDictionary:dict];
//            [[obj.class meta] save:obj];
            // this is going to be slower but more reliable than getting a list of pre-existing ids. it allows
            // the class to customize fromNetworkRepresentation
            SBDataObject *obj = [self fromNetworkRepresentation:dict session:session save:YES];
            [ret addObject:obj];
        }
        success(ret);
    }];
}

+ (void)saveBulk:(NSArray *)array withSession:(SBSession *)session key:(NSString *)existingKey // key to find existing objects, defaults to "objId"
      authorized:(BOOL)authorized success:(SBSuccessBlock)success failure:(SBErrorBlock)failure
{
    if (existingKey == nil) {
        existingKey = @"objId";
    }
    NSMutableArray *contents = [NSMutableArray arrayWithCapacity:array.count];
    for (SBDataObject *obj in array) {
        [contents addObject:[obj toNetworkRepresentation]];
    }
    NSData *dat = [contents JSONData];

    [session authorizedJSONRequestWithRequestBlock:^NSURLRequest * {
        [session.authorizedHttpClient setParameterEncoding:AFJSONParameterEncoding];
        NSMutableURLRequest *req = [session.authorizedHttpClient requestWithMethod:@"POST" path:[self bulkPath] parameters:nil];
        [req addValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [req setHTTPBody:dat];
        return req;
    } success:^(NSURLRequest *request, NSHTTPURLResponse *response, id json) {
        if (response.statusCode == 200 && [json isKindOfClass:[NSDictionary class]] && [json[@"data"] isKindOfClass:[NSArray class]]) {
            dispatch_queue_t q = (dispatch_queue_t)objc_getAssociatedObject(self, "processingQueue");
            dispatch_async(q, ^{
                [self _saveBulkObjectsFromNetwork:json[@"data"] session:session existingKey:existingKey success:success];
            });
        }
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        failure(error);
    }];
}

//
// saving --------------------------------------------------------------------------------------------------------------
//

- (void)saveInBackgroundWithBlock:(SBSuccessBlock)onSuccess failure:(SBErrorBlock)onFailure
{    
    // execute the save using the client
    NSParameterAssert(self.session != nil);
    AFHTTPClient *cli = self.authorized ? self.session.authorizedHttpClient : self.session.anonymousHttpClient;
    [self saveWithClient:cli success:onSuccess failure:onFailure];
}

- (void)saveWithClient:(AFHTTPClient *)cli success:(SBSuccessBlock)success failure:(SBErrorBlock)failure
{
    NSString *meth = @"POST";
    NSString *path = [self path];
    if (self.objId) {
        meth = @"PUT";
    }
    [cli setParameterEncoding:[self paramterEncoding]];
    
    [self.session authorizedJSONRequestWithMethod:meth path:path paramters:[self toNetworkRepresentation]
                                          success:
     ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
         if ([meth isEqualToString:@"POST"] && response.allHeaderFields[@"Location"]) {
             // got a response, it was successful, now the api wants us to
             // go elsewhere to fetch the object
             [self getRedirectResponse:response client:cli success:success failure:failure];
         } else if (response.statusCode == 200 || response.statusCode == 201) {
             dispatch_queue_t q = (dispatch_queue_t)objc_getAssociatedObject([self class], "processingQueue");
             dispatch_async(q, ^{
                 [[[self class] meta] inTransaction:^(SBModelMeta *meta, BOOL *rollback) {
                     SBDataObject *obj = self;
                     if (JSON[@"id"]) {
                         SBDataObject *existing = [[[self class] unsafeMeta] findOne:@{ @"objId": JSON[@"id"] }];
                         if (existing) {
                             // found an existing object, do not duplicate it. this can happen when the service returns
                             // an old object for save (eg if it deduplicateing things)
                             obj = existing;
                         }
                     }
                     [obj setValuesForKeysWithNetworkDictionary:JSON];
                     [meta save:obj];
                     dispatch_async(dispatch_get_main_queue(), ^{
                         success(obj);
                     });
                 }];
             });
         } else {
             // not getting a Location: header is an unknown behavior
             NSString *err = NSLocalizedString(@"An unknown error occurred. Please try again later.",
                                               @"unknown error");
             failure([NSError errorWithDomain:@"FIObjectErrorDomain"
                                         code:response.statusCode
                                     userInfo:@{ @"error": err }]);
         }
     } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
         NSString *err = NSLocalizedString(@"An unknown error occurred. Please try again later.", @"unknown error");
         if (JSON) {
             // suck the error out of the json
             if ([JSON isKindOfClass:[NSDictionary class]]) {
//                 if ([JSON allKeys].count == 1) {
//                     err = [JSON objectForKey:[JSON allKeys][0]][0];
//                 } else {
//                     err = [NSString stringWithFormat:@"%@ %@",
//                            NSLocalizedString(@"Errors:", @"errors with semicolon"),
//                            [[JSON allValues] componentsJoinedByString:@", "]];
//                 }
                 if ([JSON[@"error"] isKindOfClass:[NSString class]]) {
                     err = JSON[@"error"];
                 }
             }
         }
         failure([NSError errorWithDomain:@"FIObjectErrorDomain" code:response.statusCode userInfo:@{ @"error": err }]);
     }];
}

- (void)getRedirectResponse:(NSHTTPURLResponse *)response client:(AFHTTPClient *)cli
                    success:(SBSuccessBlock)success failure:(SBErrorBlock)failure
{
    NSMutableURLRequest *req = [cli requestWithMethod:@"GET" path:response.allHeaderFields[@"Location"] parameters:@{ }];
    AFJSONRequestOperation *op;
    op = [AFJSONRequestOperation JSONRequestOperationWithRequest:req
         success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
             dispatch_queue_t q = (dispatch_queue_t)objc_getAssociatedObject([self class], "processingQueue");
             dispatch_async(q, ^{
                 [[[self class] meta] inTransaction:^(SBModelMeta *meta, BOOL *rollback) {
                     SBDataObject *obj = self;
                     if (JSON[@"id"]) {
                         SBDataObject *existing = [[[self class] unsafeMeta] findOne:@{ @"objId": JSON[@"id"] }];
                         if (existing) {
                             // found an existing object, do not duplicate it. this can happen when the service returns
                             // an old object for save (eg if it deduplicateing things)
                             obj = existing;
                         }
                     }
                     [obj setValuesForKeysWithNetworkDictionary:JSON];
                     [meta save:obj];
                     dispatch_async(dispatch_get_main_queue(), ^{
                         success(obj);
                     });
                 }];
             });
         }
         failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
             NSString *err = NSLocalizedString(@"An unknown error occurred. Try again later.",
                                               @"unknown error");
             failure([NSError errorWithDomain:@"FIObjectErrorDomain"
                                           code:response.statusCode
                                       userInfo:@{ @"error": err }]);
         }];
    [cli enqueueHTTPRequestOperation:op];
}

+ (SBDataObjectResultSet *)getBulkWithSession:(SBSession *)sesh authorized:(BOOL)isAuthorizedRequest
{
    return [[SBDataObjectResultSet alloc] initWithDataObjectClass:self session:sesh authorized:isAuthorizedRequest];
}

+ (SBModelQuery *)bulkCacheQuery
{
    return [[[self meta] queryBuilder] query];
}

+ (SBModelQuery *)bulkCacheQueryForSession:(SBSession *)sesh
{
    return [[sesh queryBuilderForClass:self] query];
}

+ (void)get:(NSString *)objId session:(SBSession *)session success:(SBSuccessBlock)success failure:(SBErrorBlock)failure
{
    return [self get:objId pathPrefix:[self bulkPath] session:session success:success failure:failure];
}

+ (void)get:(NSString *)objId pathPrefix:(NSString *)pathPrefix session:(SBSession *)session success:(SBSuccessBlock)success failure:(SBErrorBlock)failure
{
    NSString *url = [pathPrefix stringByAppendingFormat:@"/%@", objId];
    [session authorizedJSONRequestWithMethod:@"GET" path:url paramters:@{} success:^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, id JSON) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            __block SBDataObject *obj;
            [[self meta] inTransaction:^(SBModelMeta *meta, BOOL *rollback) {
                obj = [self fromNetworkRepresentation:JSON session:session save:YES];
            }];
            dispatch_async(dispatch_get_main_queue(), ^{
                success(obj);
            });
        });
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, NSError *error, id JSON) {
        NSLog(@"%@ failed to get %@ => %@ error=%@ json=%@", self, objId, url, error, JSON);
        failure(error);
    }];
}

@end


@implementation SBDataObjectResultSetPlaceholder                @end

@implementation SBDataObjectResultSetInterstitialPlaceholder    @end

@implementation SBDataObjectResultSetMoreAvailablePlaceholder   @end


@interface SBDataObjectResultSet ()
{
    BOOL _makeAuthorizedRequests;
    NSString *_bulkPath;
    Class _dataObjectClass;
    dispatch_queue_t _processingQueue;
    NSMutableArray *_allObjects;
    NSDictionary *_beforeParams;
}

@end


@implementation SBDataObjectResultSet

@synthesize path = _bulkPath;

- (id)initWithDataObjectClass:(Class)klass session:(SBSession *)sesh authorized:(BOOL)makeAuthroizedRequests
{
    self = [super initWithQuery:[klass bulkCacheQueryForSession:sesh]];
    if (self) {
        _session = sesh;
        _makeAuthorizedRequests = makeAuthroizedRequests;
        _bulkPath = [[klass bulkPath] copy];
        _dataObjectClass = klass;
        _processingQueue = dispatch_queue_create("com.sbdata.result-set-processing-q", 0);
        _allObjects = [NSMutableArray array];
        _beforeParams = nil;
    }
    return self;
}

- (NSUInteger)count
{
    if (_allObjects.count) {
        return _allObjects.count;
    }
    return [super count];
}

- (id)objectAtIndex:(NSUInteger)idx
{
    if (_allObjects.count) {
        return [_allObjects objectAtIndex:idx];
    }
    return [super objectAtIndex:idx];
}

- (NSArray *)allObjects
{
    if (_allObjects.count) {
        return [_allObjects copy];
    }
    return [super allObjects];
}

- (NSArray *)fetchedObjects
{
    if (_allObjects.count) {
        return [_allObjects copy];
    }
    return [super fetchedObjects];
}

- (void)insertObject:(SBDataObject *)objectToAdd atIndex:(NSUInteger)index
{
    if (_allObjects.count) {
        NSMutableIndexSet *removeSet = [NSMutableIndexSet indexSet];
        [_allObjects enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
            if ([obj isEqual:objectToAdd]) {
                [removeSet addIndex:idx];
            }
        }];
        [self.delegate resultSetWillBeginUpdating:self];
        [_allObjects removeObjectsAtIndexes:removeSet];
        [self.delegate resultSet:self didRemoveObjectAtIndexes:removeSet];
        [_allObjects insertObject:objectToAdd atIndex:index];
        [self.delegate resultSet:self didInsertObjectAtIndexes:[NSIndexSet indexSetWithIndex:index]];
        [self.delegate resultSetWillEndUpdating:self];
    } else {
         // just reload
        [self.delegate resultSetWillBeginUpdating:self];
        [self.delegate resultSet:self didRemoveObjectAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [self count])]];
        [self reload];
        [self.delegate resultSet:self didInsertObjectAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [self count])]];
        [self.delegate resultSetWillEndUpdating:self];
    }
}

- (void)refresh
{
    [self.delegate resultSetWillReload:self];
    [_session authorizedJSONRequestWithMethod:@"GET" path:[self path] paramters:@{ } success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        // pass
//        NSLog(@"got json: %@", JSON);
        [self _setBeforeParams:JSON];
        dispatch_async(_processingQueue, ^{
            NSArray *replacement = [self _processPage:JSON];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self _reset:replacement];
                [self.delegate resultSetDidReload:self];
            });
        });
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        // pass
        NSLog(@"got error: %@ JSON: %@", error, JSON);
        [self.delegate resultSet:self didFailToReload:error];
    }];
}

- (void)smartRefresh
{
    [_session authorizedJSONRequestWithMethod:@"GET" path:[self path] paramters:@{} success:^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, id JSON) {
        dispatch_async(_processingQueue, ^{
            NSArray *newObjects = [self _processPage:JSON];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!_allObjects.count) {
                    [self _reset:newObjects];
                    return;
                }
                // go through all the new objects and find the first new one
                NSUInteger foundExisting = NSNotFound;
                NSUInteger startOfNew = 0;
                for (id obj in newObjects) {
                    foundExisting =  [_allObjects indexOfObject:obj];
                    if (foundExisting != NSNotFound) {
                        break;
                    }
                    startOfNew++;
                }
                NSArray *additions;
                [self.delegate resultSetWillBeginUpdating:self];
                if (foundExisting == NSNotFound) {
                    SBDataObjectResultSetInterstitialPlaceholder *placeholder = [[SBDataObjectResultSetInterstitialPlaceholder alloc] init];
                    placeholder.before = [(SBDataObject *)newObjects[0] objId];
                    [_allObjects addObject:placeholder];
                    [self.delegate resultSet:self didInsertObjectAtIndexes:[NSIndexSet indexSetWithIndex:_allObjects.count - 1]];
                    additions = newObjects;
                } else {
                    additions = [newObjects objectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(startOfNew, newObjects.count - 1)]];
                }
                NSRange addRange = NSMakeRange([self count] - 1, additions.count);
                [_allObjects addObjectsFromArray:additions];
                [self.delegate resultSet:self didInsertObjectAtIndexes:[NSIndexSet indexSetWithIndexesInRange:addRange]];
                [self.delegate resultSetWillEndUpdating:self];
            });
        });
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, NSError *error, id JSON) {
        //
    }];
}

- (void)loadMore // must have previously called -refresh
{
    if (!_beforeParams) {
        return;
    }
    [self.delegate resultSetWillLoadMore:self];
    [_session authorizedJSONRequestWithMethod:@"GET" path:[self path] paramters:_beforeParams success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        // pass
//        NSLog(@"got next page %@", JSON);
        [self _setBeforeParams:JSON];
        dispatch_async(_processingQueue, ^{
            NSArray *additions = [self _processPage:JSON];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.query.sortOrder == SBModelDescending) {
                    [self _append:additions];
                } else if (self.query.sortOrder == SBModelAscending) {
                    [self _prepend:additions];
                }
                [self.delegate resultSetDidLoadMore:self];
            });
        });
//        [self.delegate resultSetDidLoadMore:self]; -- don't do this here 
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        // pass
        NSLog(@"failed to get next page %@", error);
        [self.delegate resultSet:self didFailToLoadMore:error];
    }];
}

#define SERVER_PAGE_SIZE 20

- (void)_setBeforeParams:(NSDictionary *)JSON
{
    // if we got a full page then there might be another page. otherwise give up
    if ([JSON[@"total"] isKindOfClass:[NSNumber class]] && [JSON[@"total"] intValue] == SERVER_PAGE_SIZE
            && [JSON[@"prev_page"] isKindOfClass:[NSString class]]) {
        _beforeParams = NSDictionaryOfParametersFromURL(JSON[@"prev_page"]);
    } else {
        _beforeParams = nil;
    }
}

- (void)_reset:(NSArray *)replacement
{
    [self.delegate resultSetWillBeginUpdating:self];
    NSRange removeRange = NSMakeRange(0, [self count]);
    [_allObjects removeAllObjects];
    [self.delegate resultSet:self didRemoveObjectAtIndexes:[NSIndexSet indexSetWithIndexesInRange:removeRange]];
    [_allObjects setArray:replacement];
    [self.delegate resultSet:self didInsertObjectAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, _allObjects.count)]];
    [self.delegate resultSetWillEndUpdating:self];
}

- (void)_append:(NSArray *)additions
{
    [self.delegate resultSetWillBeginUpdating:self];
    NSRange addRange = NSMakeRange([self count] - 1, additions.count);
    [_allObjects addObjectsFromArray:additions];
    [self.delegate resultSet:self didInsertObjectAtIndexes:[NSIndexSet indexSetWithIndexesInRange:addRange]];
    [self.delegate resultSetWillEndUpdating:self];
}

- (void)_prepend:(NSArray *)additions
{
    [self.delegate resultSetWillBeginUpdating:self];
    NSRange addRange = NSMakeRange(0, additions.count);
    NSIndexSet *insertIndexes = [NSIndexSet indexSetWithIndexesInRange:addRange];
    [_allObjects insertObjects:additions atIndexes:insertIndexes];
    [self.delegate resultSet:self didInsertObjectAtIndexes:insertIndexes];
    [self.delegate resultSetWillEndUpdating:self];
}

- (SBDataObject *)_decorateObject:(SBDataObject *)obj
{
    return obj;
}

- (NSArray *)_processPage:(NSDictionary *)page
{
    NSMutableArray *all = [NSMutableArray arrayWithCapacity:[page[@"data"] count]];
    [[_dataObjectClass meta] inTransaction:^(SBModelMeta *meta, BOOL *rollback) {
        for (NSDictionary *rep in page[@"data"]) {
            SBDataObject *undecoratedObj = [_dataObjectClass fromNetworkRepresentation:rep session:self.session save:NO];
            SBDataObject *obj = [self _decorateObject:undecoratedObj]; //[[_dataObjectClass alloc] initWithSession:self.session];
            [meta save:obj];
            [all addObject:obj];
        }
    }];
    return all;
}

@end
