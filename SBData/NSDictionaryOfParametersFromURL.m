//
//  NSDictionaryOfParametersFromURL.m
//  SBData
//
//  Created by Samuel Sutch on 3/21/13.
//  Copyright (c) Steamboat Labs. All rights reserved.
//

#import "NSDictionaryOfParametersFromURL.h"

NSDictionary *NSDictionaryOfParametersFromURL(NSString *url)
{
    NSArray *parts = [url componentsSeparatedByString:@"?"];
    NSMutableDictionary *data = [[NSMutableDictionary alloc] init];
    if ([parts count] < 2) {
        return data;
    }
    NSArray *components = [parts[1] componentsSeparatedByString:@"&"];
    for (NSString *component in components) {
        NSArray *pair = [component componentsSeparatedByString:@"="];
        if (pair.count == 2) {
            if (!data[pair[0]]) {
                data[pair[0]] = [NSMutableArray array];
            }
            [data[pair[0]] addObject:pair[1]];
        }
    }
    for (NSString *key in data) { // flatten keys where that is possible
        if ([data[key] count] == 1) {
            data[key] = data[key][0];
        }
    }
    return data;
}