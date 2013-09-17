//
// SBModelQueryTerm.h
//  SBData
//
//  Created by Samuel Sutch on 3/29/13.
//  Copyright (c) Steamboat Labs. All rights reserved.
//

#import <Foundation/Foundation.h>

//
// SINGULAR -----------------------------------------------------------------
//
@protocol SBModelQueryTerm <NSObject>

@required
- (NSString *)render;
- (NSString *)renderWithNamespace:(NSString *)ns;
- (NSSet *)propNames;

@optional
- (id)initWithPropName:(NSString *)propName value:(id)val;
@property (nonatomic, readonly) id value;
@property (nonatomic, readonly) NSString *propName;

@end

// base class --------------------------------------------------------------

@interface SBModelQueryTermBase : NSObject <SBModelQueryTerm>           @end

// the actual terms --------------------------------------------------------

@interface SBModelQueryTermEquals :             SBModelQueryTermBase    @end

@interface SBModelQueryTermContainedWithin :    SBModelQueryTermBase    @end

@interface SBModelQueryTermNotEquals :          SBModelQueryTermBase    @end

//
// COMPOSITE -----------------------------------------------------------------------
//
@protocol SBModelQueryTermComposite <SBModelQueryTerm>

@optional
- (id)initWithQueryTerms:(NSArray *)terms;
@property (nonatomic, readonly) NSArray *terms;

@end

// base class ----------------------------------------------------------------------

@interface SBModelQueryTermCompositeBase : NSObject <SBModelQueryTermComposite> @end

// implementations -----------------------------------------------------------------

@interface SBModelQueryTermNot :                SBModelQueryTermCompositeBase   @end

@interface SBModelQueryTermOr :                 SBModelQueryTermCompositeBase   @end

@interface SBModelQueryTermAnd :                SBModelQueryTermCompositeBase   @end
