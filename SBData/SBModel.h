//
// SBModel.h
//  SBData
//
//  Created by Samuel Sutch on 2/14/13.
//  Copyright (c) Steamboat Labs. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SBTypes.h"
#import "SBModelQuery.h"

@class SBModelMeta;

@interface SBModel : NSObject <SBLazyField>

// what indexes in the DB
+ (NSArray *)indexes;

// what name is this stored in the DB?
+ (NSString *)tableName;

+ (SBModelMeta *)meta;
+ (SBModelMeta *)unsafeMeta; // meta which does not serialize its access to the underlying database 
+ (NSString *)name; // the name by which this model is identified, customizable
+ (void)registerModel:(Class)klass; // prepares this class for use

// every model instance is identified by a key that must be unique to all other models of the same class
@property (nonatomic, readonly) NSString *key;

// some key-value goodies for you
- (void)setValue:(id)value forKey:(NSString *)key;
- (id)valueForKey:(NSString *)key;
- (void)setValuesForKeysWithDictionary:(NSDictionary *)keyedValues;
- (void)setNilValueForKey:(NSString *)key;
- (NSArray *)allKeys;

// returns a dictionary representation of this object; it must be safely json-able
- (NSDictionary *)dictionaryValue;

// save in a transaction of it's own (use [model [meta save:model]] to create your own transactions)
// this method is THREAD SAFE - just don't call it inside a -SBModelMeta inTransaction:]
// if you are in a -SBModelMeta inTransaction] then just call -SBModelMeta save:] otherwise
// this shit will deadlock
- (void)save;

- (void)remove;

// reloads information in this object from the database
- (void)reload;

// delegate methods
- (void)willSave;
- (void)willReload;

@end


@interface SBModelResultSet : NSObject

@property (nonatomic) SBModelQuery *query;

- (NSUInteger)count;
- (id)objectAtIndex:(NSUInteger)idx;
- (NSArray *)fetchedObjects;
- (NSArray *)allObjects;
- (void)reload;
- (id)first;

- (id)initWithQuery:(SBModelQuery *)query;

@end


@interface SBModelMeta : NSObject <NSCopying>

@property (nonatomic) BOOL unsafe;

+ (void)initDb;

- (id)initWithModelClass:(Class)kls;

// saves the model to the db and saves its index
// NOT (!) THREAD SAFE - use inTransaction: or inDeferredTransaction:
- (void)save:(SBModel *)obj;

// removes from the model from the db and removes related indexes
// NOT THREAD SAFE
- (void)remove:(SBModel *)obj;

// remove all models and their indexes from the DB
// NOT THREAD SAFE
- (void)removeAll;

// reloads the model from the database
// NOT THREAD SAFE - use inDeferredTransaction or inTransaction
- (void)reload:(SBModel *)obj;

// create the database and such - THREAD SAFE
- (void)initDb;

// synchronizing access to theSBModelMeta so operations can be preformed in other threads
- (void)inTransaction:(void(^)(SBModelMeta *meta, BOOL *rollback))transactionBlock;
- (void)inDeferredTransaction:(void (^)(SBModelMeta *meta, BOOL *rollback))block;

- (SBModelResultSet *)findWithProperties:(NSDictionary *)properties
                                 orderBy:(NSArray *)orderBy
                                 sorting:(SBModelSorting)sort;
- (id)findOne:(NSDictionary *)properties;
- (id)findByKey:(NSString *)key;
- (SBModelQueryBuilder *)queryBuilder;

@end
