//
// SBModelQuery.h
//  SBData
//
//  Created by Samuel Sutch on 3/29/13.
//  Copyright (c) Steamboat Labs. All rights reserved.
//

#import <Foundation/Foundation.h>

@class SBModel;
@class SBModelMeta;
@class SBModelResultSet;
@class SBModelQueryBuilder;

typedef enum {
    SBModelAscending,
    SBModelDescending
} SBModelSorting;


@interface SBModelQuery : NSObject

@property (nonatomic, readonly) NSDictionary *parameters;
@property (nonatomic, readonly) NSArray *orderBy;
@property (nonatomic, readonly) SBModelSorting sortOrder;
@property (nonatomic, readonly) id (^decorator)(SBModel *);

- (id)initWithMeta:(SBModelMeta *)meta;
- (SBModelResultSet *)results;
- (NSUInteger)count;
- (NSArray *)fetchOffset:(NSInteger)offset count:(NSInteger)count includeRelated:(BOOL)includeRelated;
- (void)removeAll; // this executes inside its own transaction (but should it?)
- (void)removeAllUnsafe;
- (SBModelQueryBuilder *)builder;

@end


@interface SBModelQueryBuilder : NSObject

- (id)initWithMeta:(SBModelMeta *)meta;

- (SBModelQueryBuilder *)property:(NSString *)propName isEqualTo:(id)obj;
- (SBModelQueryBuilder *)property:(NSString *)propName isContainedWithin:(NSSet *)set;
- (SBModelQueryBuilder *)property:(NSString *)propName isNotCointainedWithinSet:(NSSet *)set;
- (SBModelQueryBuilder *)property:(NSString *)propName isNotEqualTo:(id)obj;
- (SBModelQueryBuilder *)properties:(NSArray *)propNames areNotEqualTo:(NSArray *)values;
- (SBModelQueryBuilder *)propertyTuple:(NSArray *)propNames isContainedWithinValueTuples:(NSSet *)set; // eg [(firstName, lastName)] is contained within {("samuel", "sutch"), ("brandom", "smalls"), ("fart", "mcgeezles")} - all value tuples must be the same length as the property tuple
- (SBModelQueryBuilder *)propertyTuple:(NSArray *)propNames isNotContainedWithinValueTuples:(NSSet *)set;
- (SBModelQueryBuilder *)sort:(SBModelSorting)sortOrder;
- (SBModelQueryBuilder *)orderByProperties:(NSArray *)orderingProperties;
- (SBModelQueryBuilder *)decorateResults:(id(^)(SBModel *instance))decorator;

- (SBModelQuery *)query;

@end
