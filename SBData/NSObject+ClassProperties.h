//
//  NSObject+ClassProperties.h
//  SBData
//
//  Created by Samuel Sutch on 2/15/13.
//  Copyright (c) Steamboat Labs. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSObject (ClassProperties)

+ (NSDictionary *)propertiesForClass:(Class)klass;
+ (NSDictionary *)propertiesForClass:(Class)klass traversingParentsToClass:(Class)klassStop;

@end
