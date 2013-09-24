//
// SBModel_SBModelPrivate.h
//  SBData
//
//  Created by Samuel Sutch on 3/29/13.
//  Copyright (c) Steamboat Labs. All rights reserved.
//

#import "SBModel.h"
#import <FMDB/FMDatabase.h>
#import "sqlite3.h"
#import <JSONKit/JSONKit.h>
#import <objc/runtime.h>
#import "NSObject+ClassProperties.h"

#define PRIVATE_UUID_KEY @"_uuid_"

static inline void LogStmt(NSString *fmt, ...) {
//    va_list args;
//    va_start(args, fmt);
//    NSLogv(fmt, args);
//    va_end(args);
}

static inline NSString *FormatContainer(id obj) {
    NSMutableString *s = [NSMutableString string];
    if ([obj isKindOfClass:[NSString class]]) {
        [s setString:obj];
    } else if ([obj isKindOfClass:[NSArray class]]) {
        [s appendString:@"["];
        for (id sub in obj) {
            [s appendString:FormatContainer(sub)];
            if (sub != [obj lastObject]) {
                [s appendString:@", "];
            }
        }
        [s appendString:@"]"];
    } else if ([obj isKindOfClass:[NSDictionary class]]) {
        NSArray *keys = [obj allKeys];
        [s appendString:@"{"];
        for (id key in keys) {
            [s appendFormat:@"%@=%@", FormatContainer(key), FormatContainer(obj[key])];
            if (key != [keys lastObject]) {
                [s appendString:@", "];
            }
        }
        [s appendString:@"}"];
    }
    return s;
}

@interface SBModel ()

- (void)setKey:(NSString *)key;
- (void)setValuesForKeysWithDatabaseDictionary:(NSDictionary *)keyedValues; // same as setValuesForKeysWithDictionary except it respectsSBField coercion

+ (Class)classForPropertyName:(NSString *)propName;
+ (NSArray *)allFieldNames;

@end


@interface SBModelMeta ()

// helper to get a list of the index-table table names
- (NSArray *)_getIndexTableNames;
- (void)_populateIndex:(NSString *)tableName fieldNames:(NSArray *)fieldNames key:(NSString *)key values:(NSDictionary *)dict;

- (FMDatabase *)writeDatabase;
- (FMDatabase *)readDatabase;
- (void)inDatabase:(void (^)(FMDatabase *db))block;
- (void)beginTransaction:(BOOL)useDeferred withBlock:(void (^)(SBModelMeta *meta, BOOL *rollback))block;

@property (nonatomic, readonly) NSArray *indexes;
@property (nonatomic, readonly) NSString *name;
@property (nonatomic, readonly) Class modelClass;

@end
