//
// SBTypes.m
//  SBData
//
//  Created by Samuel Sutch on 3/12/13.
//  Copyright (c) Steamboat Labs. All rights reserved.
//

#import "SBTypes.h"

//
// INTEGER -------------------------------------------------------------------------------------------------------------
//
@interface SBInteger ()
{
    NSInteger _value;
}
@property (nonatomic, readonly) NSInteger value;
@end

@implementation SBInteger

@synthesize value = _value;

- (NSString *)toDatabase { return [self description]; }

+ (instancetype)fromDatabase:(NSString *)str
{
    NSInteger intVal = [str integerValue];
    return [[self alloc] initWithInteger:intVal];
}

+ (NSString *)databaseType { return @"INTEGER"; }

- (NSString *)description
{
    return [NSString stringWithFormat:@"%d", _value];
}

- (BOOL)isEqual:(id)object
{
    if (![object isKindOfClass:[self class]]) {
        return NO;
    }
    SBInteger *other = (SBInteger *)object;
    return other.value == _value;
}

- (NSInteger)integerValue
{
    return _value;
}

- (id)initWithInteger:(NSInteger)integer
{
    self = [super init];
    if (self) {
        _value = integer;
    }
    return self;
}

@end

//
// FLOAT ---------------------------------------------------------------------------------------------------------------
//

@interface SBFloat ()
{
    float _value;
}

@end

@implementation SBFloat

- (NSString *)toDatabase { return [self description]; }

+ (instancetype)fromDatabase:(NSString *)str { return [[self alloc] initWithFloat:[str floatValue]]; }

+ (NSString *)databaseType { return @"REAL"; }

- (NSString *)description
{
    return [NSString stringWithFormat:@"%f", _value];
}

- (float)floatValue
{
    return _value;
}

- (id)initWithFloat:(float)flote
{
    self = [super init];
    if (self) {
        _value = flote;
    }
    return self;
}

@end

//
// STRING --------------------------------------------------------------------------------------------------------------
//

@implementation SBString

- (NSString *)toDatabase { return self; }

+ (instancetype)fromDatabase:(NSString *)str { return [[self alloc] initWithString:str]; }

+ (NSString *)databaseType { return @"TEXT"; }

@end

//
// DATE ----------------------------------------------------------------------------------------------------------------
//

static NSDateFormatter *_dateFormatter = nil;

NSDateFormatter *dateFormatter() {
    if (!_dateFormatter) {
        _dateFormatter = [[NSDateFormatter alloc] init];
        [_dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSSZZZ"];
    }
    return _dateFormatter;
}

@interface SBDate ()
{
    NSDate *_underlyingDate;
}

@end

@implementation SBDate

- (id)initWithDate:(NSDate *)date
{
    self = [super init];
    if (self) {
        _underlyingDate = date;
    }
    return self;
}

// primitive overrides
- (id)initWithTimeIntervalSinceReferenceDate:(NSTimeInterval)secsToBeAdded
{
    self = [super init];
    if (self) {
        _underlyingDate = [NSDate dateWithTimeIntervalSinceReferenceDate:secsToBeAdded];
    }
    return self;
}

- (NSTimeInterval)timeIntervalSinceReferenceDate
{
    return [_underlyingDate timeIntervalSinceReferenceDate];
}

// SBField protocol
- (NSString *)toDatabase { return [self description]; }

- (NSString *)description { return [dateFormatter() stringFromDate:self]; }

+ (instancetype)fromDatabase:(NSString *)str
{
    return [[self alloc] initWithTimeInterval:0 sinceDate:[dateFormatter() dateFromString:str]];
}

+ (NSString *)databaseType { return @"TEXT"; }

@end
