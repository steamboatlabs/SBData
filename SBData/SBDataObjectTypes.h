//
//  SBDataObjectTypes.h
//  Pods
//
//  Created by Samuel Sutch on 9/24/13.
//
//

#import <Foundation/Foundation.h>
#import "SBTypes.h"

// takes care of coercing field values from their network representation
// into the local representation (eg taking a ISO8601 date and making it an SBDate)

@protocol SBNetworkFieldConverting <NSObject>

// may return nil
- (id<SBField>)fromNetwork:(id)value;

// should NEVER return nil
- (id)toNetwork:(id<SBField>)value;

@end


@interface SBIntegerConverter : NSObject <SBNetworkFieldConverting>
@end

@interface SBFloatConverter : NSObject <SBNetworkFieldConverting>
@end

@interface SBStringConverter : NSObject <SBNetworkFieldConverting>
@end

@interface SBISO8601DateConverter : NSObject <SBNetworkFieldConverting>
@end