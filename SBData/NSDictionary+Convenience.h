//
//  NSDictionary+Convenience.h
//  SBData
//
//  Created by Samuel Sutch on 2/18/13.
//  Copyright (c) Steamboat Labs. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSDictionary (Convenience)

- (NSDictionary *)dictionaryByMergingWithDictionary:(NSDictionary *)other;

@end
