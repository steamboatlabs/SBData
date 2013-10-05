//
// SBTypes.h
//  SBData
//
//  Created by Samuel Sutch on 3/12/13.
//  Copyright (c) Steamboat Labs. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol SBField <NSObject>

- (NSString *)toDatabase;
+ (instancetype)fromDatabase:(NSString *)str;
+ (NSString *)databaseType;

@end

// property types

@interface SBInteger : NSObject <SBField>
- (id)initWithInteger:(NSInteger)integer;
- (NSInteger)integerValue;
@end


@interface SBFloat : NSObject <SBField>
- (id)initWithFloat:(float)flote;
- (float)floatValue;
@end


@interface SBString : NSString <SBField>
@end


@interface SBDate : NSDate <SBField>
- (id)initWithDate:(NSDate *)date;
@end


@protocol SBLazyField <SBField>

// generates an instance of the class but waits until it's accessed to deserialize
+ (instancetype)fromDatabaseLazy:(NSString *)dbVal;

// fills in the deserialized value from an arbitrary value
- (void)populate:(id)val;

// fills in the deserialized value from the database valeu
- (void)populate;

- (BOOL)isPopulated;

@end
