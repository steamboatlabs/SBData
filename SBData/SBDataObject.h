//
// SBDataObject.h
//  SBData
//
//  Created by Samuel Sutch on 2/11/13.
//  Copyright (c) Steamboat Labs. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AFNetworking/AFNetworking.h>
#import <AFOAuth2Client/AFOAuth2Client.h>
#import "SBSession.h"
#import "SBModel.h"

@class SBDataObjectResultSet; // a remote result set

@interface SBDataObject : SBModel

// should be implemented by subclasses. returns a dictionary of local property keys eg "firstName" that map to
// the keys of the network representation e.g. "first_name"
+ (NSDictionary *)propertyToNetworkKeyMapping;

// serializing to/from the network representation
- (NSDictionary *)toNetworkRepresentation;
- (void)setValuesForKeysWithNetworkDictionary:(NSDictionary *)keyedValues;

// the below two methods should be executed inside a transaction - ie they are unsafe 
+ (instancetype)findWithNetworkRepresentation:(NSDictionary *)dict session:(SBSession *)session; // informs the below method of existing objects from the network
+ (instancetype)fromNetworkRepresentation:(NSDictionary *)dict session:(SBSession *)session save:(BOOL)persist; // creates or updates an object from the network

// more-or-less static properties that determine where stuff is stored
+ (NSString *)bulkPath;
@property (nonatomic) NSString *listPath;           // eg "/users"
@property (nonatomic) NSString *detailPathSpec;     // eg "/user/$id"
@property (nonatomic) BOOL authorized;              // whether to use the authenticated endpoints DEFAULT=YES
- (AFHTTPClientParameterEncoding)paramterEncoding;  // what paramter encoding to use DEFAULT=AFJSONParameterEncoding
- (NSString *)path;                                 // the path to this specific object, used for editing and such

// this object is tied to this session
@property (nonatomic) SBSession *session;

// if the object is already saved (self.data["id"] is filled out) it will make a PUT
// otherwise it will make a POST, follow the redirect and fill out any dynamic fields from the
// api (eg "api")
- (void)saveInBackgroundWithBlock:(SBSuccessBlock)onSuccess failure:(SBErrorBlock)onFailure;

- (void)removeInBackgroundWithBlock:(SBSuccessBlock)onSuccess failure:(SBErrorBlock)onFailure;

- (void)refreshInBackgroundWithBlock:(SBSuccessBlock)onSuccess failure:(SBErrorBlock)onFailure;

- (void)updateInBackgroundWithBlock:(SBSuccessBlock)onSuccess failure:(SBErrorBlock)onFailure;

- (void)updateWithNetworkRepresentation:(NSDictionary *)representation
                                success:(SBSuccessBlock)onSuccess
                                failure:(SBErrorBlock)onFailure;

+ (void)createWithNetworkRepresentation:(NSDictionary *)representation
                                session:(SBSession *)session
                                success:(SBSuccessBlock)success
                                failure:(SBErrorBlock)failure;

// delete all cached objects then reload them from the network resource
// this method does not paginate resources which are paginated, it will get just the first page
+ (void)reloadEntireCollectionFromNetworkSession:(SBSession *)session
                                      authorized:(BOOL)isAuthorizedUser
                                         success:(SBSuccessBlock)success
                                         failure:(SBErrorBlock)failure;

+ (void)saveBulk:(NSArray *)array withSession:(SBSession *)session key:(NSString *)existingKey // key to find existing objects, defaults to "objId"
      authorized:(BOOL)authorized success:(SBSuccessBlock)success failure:(SBErrorBlock)failure;

- (id)initWithSession:(SBSession *)sesh;

// data model properties
@property (nonatomic) NSString *objId; // all objects from the server have an ID
@property (nonatomic) NSString *userKey; // all objects are tied to a user

+ (SBDataObjectResultSet *)getBulkWithSession:(SBSession *)sesh authorized:(BOOL)isAuthorizedRequest;
+ (SBDataObjectResultSet *)getBulkPath:(NSString *)path withSession:(SBSession *)sesh authorized:(BOOL)isAuthorizedReq;
+ (SBDataObjectResultSet *)getBulkPath:(NSString *)path
                            cacheQuery:(SBModelQuery *)q
                           withSession:(SBSession *)sesh
                            authorized:(BOOL)isAuthorizedReq;
+ (SBModelQuery *)bulkCacheQuery; // returns the query that is used as the cache
+ (SBModelQuery *)bulkCacheQueryForSession:(SBSession *)sesh;

+ (void)get:(NSString *)objId session:(SBSession *)session success:(SBSuccessBlock)success failure:(SBErrorBlock)failure;
+ (void)get:(NSString *)objId pathPrefix:(NSString *)pathPrefix session:(SBSession *)session success:(SBSuccessBlock)success failure:(SBErrorBlock)failure;

@end


@protocol SBDataObjectResultSetDelegate <NSObject>

@optional
- (void)resultSetWillBeginUpdating:(SBDataObjectResultSet *)resultSet;
- (void)resultSet:(SBDataObjectResultSet *)resultSet didInsertObjectAtIndexes:(NSIndexSet *)idx;
- (void)resultSet:(SBDataObjectResultSet *)resultSet didRemoveObjectAtIndexes:(NSIndexSet *)idx;
- (void)resultSetWillEndUpdating:(SBDataObjectResultSet *)resultSet;

- (void)resultSetWillReload:(SBDataObjectResultSet *)resultSet;
- (void)resultSetDidReload:(SBDataObjectResultSet *)resultSet;
- (void)resultSet:(SBDataObjectResultSet *)resultSet didFailToReload:(NSError *)error;

- (void)resultSetWillLoadMore:(SBDataObjectResultSet *)resultSet;
- (void)resultSetDidLoadMore:(SBDataObjectResultSet *)resultSet;
- (void)resultSet:(SBDataObjectResultSet *)resultSet didFailToLoadMore:(NSError *)error;

@end

// placeholders inserted into the result set when there is more known to be available
@interface SBDataObjectResultSetPlaceholder : NSObject

@property (nonatomic, copy) NSString *before;
@property (nonatomic, copy) NSString *after;

@end

@interface SBDataObjectResultSetInterstitialPlaceholder : SBDataObjectResultSetPlaceholder

@end

@interface SBDataObjectResultSetMoreAvailablePlaceholder : SBDataObjectResultSetPlaceholder

@end


@interface SBDataObjectResultSet : SBModelResultSet

@property (nonatomic, weak) NSObject<SBDataObjectResultSetDelegate> *delegate;
@property (nonatomic, readonly) SBSession *session;
@property (nonatomic) NSString *path;
@property (nonatomic) BOOL clearsCollectionBeforeSaving;

- (id)initWithDataObjectClass:(Class)klass session:(SBSession *)sesh authorized:(BOOL)makeAuthroizedRequests;
- (id)initWithDataObjectClass:(Class)klass
                         path:(NSString *)path
                      session:(SBSession *)sesh
                   authorized:(BOOL)makeAuthroizedRequests;
- (id)initWithDataObjectClass:(Class)klass
                         path:(NSString *)path
                   cacheQuery:(SBModelQuery *)query
                      session:(SBSession *)sesh
                   authorized:(BOOL)makeAuthroizedRequests;

- (void)refresh;
- (void)loadMore;

- (void)smartRefresh;
- (void)loadMoreWithPlaceholder:(SBDataObjectResultSetPlaceholder *)placeholder;

- (void)insertObject:(SBDataObject *)object atIndex:(NSUInteger)index;

// alter or replace an object before it is saved. override this in subclasses to customize behavior
- (SBDataObject *)_decorateObject:(SBDataObject *)obj;

@end
