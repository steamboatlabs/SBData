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
