//
// SBUser.h
//  SBData
//
//  Created by Samuel Sutch on 2/11/13.
//  Copyright (c) Steamboat Labs. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "SBDataObject.h"

@interface SBUser : SBDataObject

@property (nonatomic) NSString *email;

- (NSString *)emailSuffix;

@end
