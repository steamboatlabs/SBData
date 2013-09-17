//
// SBUser.m
//  SBData
//
//  Created by Samuel Sutch on 2/11/13.
//  Copyright (c) Steamboat Labs. All rights reserved.
//

#import "SBUser.h"
#import "NSDictionary+Convenience.h"

@implementation SBUser

@dynamic email;

+ (NSString *)tableName { return @"users"; }

+ (NSArray *)indexes { return [[super indexes] arrayByAddingObjectsFromArray:@[ @[ @"email" ] ]]; }

+ (NSDictionary *)propertyToNetworkKeyMapping
{
    return [[super propertyToNetworkKeyMapping] dictionaryByMergingWithDictionary:@{
                @"email":                   @"email",
            }];
}

+ (void)load
{
    [self registerModel:self];
}

- (NSString *)emailSuffix
{
    return [self.email substringFromIndex:[self.email rangeOfString:@"@" options:NSBackwardsSearch].location + 1];
}

@end
