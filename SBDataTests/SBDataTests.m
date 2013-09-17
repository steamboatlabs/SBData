//
//  SBDataTests.m
//  SBDataTests
//
//  Created by Samuel Sutch on 9/10/13.
//  Copyright (c) 2013 Steamboat Labs. All rights reserved.
//

#import "SBDataTests.h"
#import <SBData/SBData.h>

// EXAMPLE MODELS ------------------------------------------------------------------------------------------

@interface SomeModel : SBModel

@property(nonatomic) NSString *str;

@end

@implementation SomeModel

@dynamic str;

+ (NSString *)tableName { return @"some-model"; }
+ (void)load { [self registerModel:self]; }

@end

// ACTUAL TESTS --------------------------------------------------------------------------------------------

@implementation SBDataTests

- (void)setUp
{
    [super setUp];
    
    // Set-up code here.
}

- (void)tearDown
{
    // Tear-down code here.
    
    [super tearDown];
}

- (void)testExample
{
    SomeModel *mod = [[SomeModel alloc] init];
    mod.str = @"value";
    
    STAssertNil(mod.key, @"must not have a key before saving");
    
    [mod save];
    
    STAssertNotNil(mod.key, @"must have a key when done saving");
    
    SomeModel *retMod = [[SomeModel meta] findOne:@{ @"str": @"value" }];
    
    STAssertNotNil(retMod, @"must be able to find easly from the db");
    STAssertTrue([retMod isEqual:mod], @"models must be equal"); // this just checks the key
    STAssertTrue([retMod.str isEqualToString:@"value"], @"model value must be what is expected");
}

@end
