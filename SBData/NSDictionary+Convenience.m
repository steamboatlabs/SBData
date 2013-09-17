//
//  NSDictionary+Convenience.m
//  SBData
//
//  Created by Samuel Sutch on 2/18/13.
//  Copyright (c) Steamboat Labs. All rights reserved.
//

#import "NSDictionary+Convenience.h"

@implementation NSDictionary (Convenience)

- (NSDictionary *)dictionaryByMergingWithDictionary:(NSDictionary *)other
{
    NSMutableDictionary *d1 = [self mutableCopy];
    for (id k in other) {
        [d1 setObject:other[k] forKey:k];
    }
    return [d1 copy];
}

@end
