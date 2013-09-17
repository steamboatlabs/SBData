//
// SBModelQueryTerm.m
//  SBData
//
//  Created by Samuel Sutch on 3/29/13.
//  Copyright (c) Steamboat Labs. All rights reserved.
//

#import "SBModelQueryTerm.h"
#import "sqlite3.h"


@implementation SBModelQueryTermBase
{
    NSString *_propName;
    id _value;
}

@synthesize propName = _propName;
@synthesize value = _value;

- (id)initWithPropName:(NSString *)propName value:(id)val
{
    self = [super init];
    if (self) {
        _propName = [propName copy];
        _value = val;
    }
    return self;
}

- (NSString *)render { return @""; }

- (NSString *)renderWithNamespace:(NSString *)ns { return [NSString stringWithFormat:@"%@.%@", ns, [self render]]; }

- (NSSet *)propNames { return [NSSet setWithObject:_propName]; }

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %@>", NSStringFromClass([self class]), [self render]];
}

@end


@implementation SBModelQueryTermEquals

- (NSString *)render
{
    char *escaped = sqlite3_mprintf("'%q'", [[self.value description] UTF8String]);
    NSString *ret = [NSString stringWithFormat:@"%@ = %s", self.propName, escaped];
    sqlite3_free(escaped);
    return ret;
}

@end


@implementation SBModelQueryTermContainedWithin

- (NSString *)render
{
    NSMutableArray *escapedValues = [NSMutableArray arrayWithCapacity:[self.value count]];
    NSArray *arrayValue = [self.value allObjects];
    for (id el in arrayValue) {
        char *escaped = sqlite3_mprintf("'%q'", [[el description] UTF8String]);
        [escapedValues addObject:[NSString stringWithUTF8String:(const char *)escaped]];
        sqlite3_free(escaped);
    }
    return [NSString stringWithFormat:@"%@ IN(%@)", self.propName, [escapedValues componentsJoinedByString:@", "]];
}

@end


@implementation SBModelQueryTermNotEquals

- (NSString *)render
{
    char *escaped = sqlite3_mprintf("'%q'", [[self.value description] UTF8String]);
    NSString *ret = [NSString stringWithFormat:@"%@ != %s", self.propName, escaped];
    sqlite3_free(escaped);
    return ret;
}

@end


@implementation SBModelQueryTermCompositeBase
{
    NSArray *_terms;
    NSSet *_props;
}

@synthesize terms = _terms;

- (id)initWithQueryTerms:(NSArray *)terms
{
    self = [super init];
    if (self) {
        _terms = terms;
        NSMutableSet *props = [NSMutableSet set];
        for (NSObject<SBModelQueryTerm> *term in terms) {
            for (id p in term.propNames) {
                [props addObject:p];
            }
        }
        _props = props;
    }
    return self;
}

- (NSSet *)propNames
{
    return _props;
}

- (id)value
{
    if (_terms.count == 1) {
        return [(id<SBModelQueryTerm>)[_terms objectAtIndex:0] value];
    }
    return nil;
}

- (NSArray *)_allTermsRendered:(NSString *)ns
{
    NSMutableArray *vals = [NSMutableArray arrayWithCapacity:_terms.count];
    for (NSObject<SBModelQueryTerm> *term in _terms) {
        [vals addObject:(ns ? [term renderWithNamespace:ns] : [term render])];
    }
    return vals;
}

- (NSString *)_allTermsRendered:(NSString *)ns joiner:(NSString *)joiner
{
    NSMutableString *s = [NSMutableString stringWithFormat:@"("];
    NSString *j = [NSString stringWithFormat:@") %@ (", joiner];
    [s appendString:[[self _allTermsRendered:ns] componentsJoinedByString:j]];
    [s appendString:@")"];
    return s;
}

- (NSString *)render
{
    return [[self _allTermsRendered:nil] componentsJoinedByString:@", "];
}

- (NSString *)renderWithNamespace:(NSString *)ns
{
    return [[self _allTermsRendered:ns] componentsJoinedByString:@", "];
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@ %@>", NSStringFromClass([self class]), [self render]];
}

@end


@implementation SBModelQueryTermNot

- (NSString *)render
{
    return [NSString stringWithFormat:@"NOT(%@)", [[self _allTermsRendered:nil] componentsJoinedByString:@" AND "]];
}

- (NSString *)renderWithNamespace:(NSString *)ns
{
    return [NSString stringWithFormat:@"NOT(%@)", [[self _allTermsRendered:ns] componentsJoinedByString:@" AND "]];
}

@end


@implementation SBModelQueryTermOr

- (NSString *)render
{
//    return [[self _allTermsRendered:nil] componentsJoinedByString:@" OR "];
    return [self _allTermsRendered:nil joiner:@"OR"];
}

- (NSString *)renderWithNamespace:(NSString *)ns
{
//    return [[self _allTermsRendered:ns] componentsJoinedByString:@" OR "];
    return [self _allTermsRendered:ns joiner:@"OR"];
}

@end


@implementation SBModelQueryTermAnd

- (NSString *)render
{
//    return [[self _allTermsRendered:nil] componentsJoinedByString:@" AND "];
    return [self _allTermsRendered:nil joiner:@"AND"];
}

- (NSString *)renderWithNamespace:(NSString *)ns
{
//    return [[self _allTermsRendered:ns] componentsJoinedByString:@" AND "];
    return [self _allTermsRendered:ns joiner:@"AND"];
}

@end
