//
// SBSession.m
//  SBData
//
//  Created by Samuel Sutch on 2/11/13.
//  Copyright (c) Steamboat Labs. All rights reserved.
//

#import "SBSession.h"
#import <AFNetworking/AFHTTPClient.h>
#import <AFNetworking/AFHTTPRequestOperation.h>
#import <AFNetworking/AFJSONRequestOperation.h>
#import <AFOAuth2Client/AFOAuth2Client.h>
#import <SecureUDID/SecureUDID.h>
#import "SBUser.h"
#import "SBDataObject.h"
#import "NSDictionary+Convenience.h"
#import <AFHTTPRequestOperationLogger/AFHTTPRequestOperationLogger.h>

NSString *SBLoginDidBecomeInvalidNotification           = @"SBLoginDidBecomeInvalidNotification";
NSString *SBLogoutNotification                          = @"SBLogoutNotification";
NSString *SBDidReceiveRemoteNotification                = @"SBDidReceiveRemoteNotification";
NSString *SBDidReceiveRemoteNotificationAuthorization   = @"SBDidReceiveRemoteNotificationAuthorization";

//
// AFNetworking subclasses ---------------------------------------------------------------------------------------------
//

@implementation SBJSONRequestOperation

- (BOOL)allowsInvalidSSLCertificate
{
    NSNumber *allow = [[NSBundle mainBundle] objectForInfoDictionaryKey:SBApiAllowUntrustedCertificateKey];
    if (!allow) {
        return NO;
    }
    return [allow boolValue];
}

@end

@interface SBHTTPClient : AFHTTPClient
@end

@implementation SBHTTPClient

- (NSMutableURLRequest *)requestWithMethod:(NSString *)method path:(NSString *)path parameters:(NSDictionary *)parameters
{

    NSMutableURLRequest *req = [super requestWithMethod:method path:path parameters:parameters];
    [req setHTTPShouldHandleCookies:NO];
    return req;
}

@end


@interface SBOAuth2Client : AFOAuth2Client
@end

@implementation SBOAuth2Client

- (NSMutableURLRequest *)requestWithMethod:(NSString *)method path:(NSString *)path parameters:(NSDictionary *)parameters
{
    NSMutableURLRequest *req = [super requestWithMethod:method path:path parameters:parameters];
    [req setHTTPShouldHandleCookies:NO];
    return req;
}

- (AFHTTPRequestOperation *)HTTPRequestOperationWithRequest:(NSURLRequest *)urlRequest
                                                    success:(void (^)(AFHTTPRequestOperation *, id))success
                                                    failure:(void (^)(AFHTTPRequestOperation *, NSError *))failure
{
    AFHTTPRequestOperation *op = [super HTTPRequestOperationWithRequest:urlRequest success:success failure:failure];
    NSNumber *allow = [[NSBundle mainBundle] objectForInfoDictionaryKey:SBApiAllowUntrustedCertificateKey];
    if (!allow) {
        op.allowsInvalidSSLCertificate = NO;
    } else {
        op.allowsInvalidSSLCertificate = [allow boolValue];
    }
    return op;
}

@end

//
// Actual Implementation -----------------------------------------------------------------------------------------------
//

@implementation SBSessionData

@dynamic userKey;
@dynamic s3Bucket;
@dynamic s3UploadPrefix;
@dynamic prefs;

+ (NSString *)tableName { return @"sessiondata"; }

+ (NSArray *)indexes { return [[super indexes] arrayByAddingObjectsFromArray:@[ @[ @"userKey" ] ]]; }

+ (void)load
{
    [self registerModel:self];
}

- (NSDictionary *)prefs
{
    if (![self valueForKey:@"prefs"]) {
        [self setValue:[NSDictionary dictionary] forKey:@"prefs"];
    }
    return [self valueForKey:@"prefs"];
}

- (void)setPrefValue:(id)val forKey:(id<NSCopying>)key
{
    self.prefs = [self.prefs dictionaryByMergingWithDictionary:@{ key: val }];
    [self save];
}

@end


@interface SBSession ()
{
    AFOAuthCredential *_apiCredential;
    Class _userClass;
}

@property (nonatomic) AFHTTPClient *anonymousHttpClient;
@property (nonatomic) AFOAuth2Client *authorizedHttpClient;
@property (nonatomic) AFOAuthCredential *apiCredential;
@property (nonatomic) NSString *apiMountPointSpec;
@property (nonatomic) NSString *apiVersion;
@property (nonatomic) SBUser *user;
@property (nonatomic) SBSessionData *sessionData;


- (void)_configureHttpClient:(AFHTTPClient *)cli;

- (void)getOAuth:(SBUser *)user password:(NSString *)password success:(SBSuccessBlock)onSuccess failure:(SBErrorBlock)onError;

@end

@implementation SBSession

+ (instancetype)lastUsedSessionWithUserClass:(Class)userClass
{
    NSUserDefaults *userDefs = [NSUserDefaults standardUserDefaults];
    NSString *ident = [userDefs stringForKey:@"SBLastSessionIdentifier"];
    NSLog(@"reviving session identifier: %@", ident);
    if (ident != nil) {
        NSString *email = [self emailAddressForIdentifier:ident userClass:userClass];
        return [self sessionWithEmailAddress:email userClass:userClass];
    }
    return nil;
}

+ (void)setLastUsedSession:(SBSession *)session
{
    NSUserDefaults *userDefs = [NSUserDefaults standardUserDefaults];
    if (session == nil) {
        [userDefs removeObjectForKey:@"SBLastSessionIdentifier"];
    } else {
        [userDefs setObject:session.identifier forKey:@"SBLastSessionIdentifier"];
    }
    [userDefs synchronize];
}

static NSMutableDictionary *_sessionByEmailAddress = nil;

+ (void)initialize
{
    static BOOL didInitialize = NO;
    if (!didInitialize) {
        didInitialize = YES;
        _sessionByEmailAddress = [[NSMutableDictionary alloc] init];
    }
}

+ (instancetype)sessionWithEmailAddress:(NSString *)email userClass:(__unsafe_unretained Class)klass
{
    if (!email) {
        return nil;
    }
    if (!_sessionByEmailAddress[email]) {
        _sessionByEmailAddress[email] = [[self alloc] initWithEmailAddress:email userClass:klass];
    }
    return _sessionByEmailAddress[email];
}

+ (instancetype)anonymousSession
{
    return [[self alloc] initWithIdentifier:nil userClass:[SBUser class]];
}

+ (NSString *)emailAddressForIdentifier:(NSString *)ident userClass:(Class)userClass
{
    SBSessionData *meta = [[SBSessionData meta] findByKey:ident];
    if (meta) {
        SBUser *user = [[userClass meta] findByKey:meta.userKey];
        if (user) {
            return user.email;
        }
    }
    return nil;
}

- (id)initWithIdentifier:(NSString *)identifier userClass:(Class)userClass
{
    self = [super init];
    [[AFHTTPRequestOperationLogger sharedLogger] startLogging];
    if (self) {
        _userClass = userClass;
        _apiMountPointSpec = [[NSBundle mainBundle] objectForInfoDictionaryKey:SBApiBaseURLKey];
        _apiVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:SBApiVersionKey];
        if (identifier != nil) {
            _sessionData = [[SBSessionData meta] findByKey:identifier];
            _user = [[userClass meta] findByKey:_sessionData.userKey];
        } else {
            // fresh session
            _sessionData = [[SBSessionData alloc] init];
        }
    }
    return self;
}

- (id)initWithEmailAddress:(NSString *)emailAddy userClass:(Class)userClass
{
    self = [self initWithIdentifier:nil userClass:userClass];
    [[AFHTTPRequestOperationLogger sharedLogger] startLogging];
    if (self && emailAddy != nil) {
        // try to find an existingSBUser with that email
        SBUser *user = [[userClass meta] findOne:@{ @"email": emailAddy }];
        NSLog(@"user: %@", user);
        if (user != nil) {
            // now try to find an existing session with that data
            SBSessionData *session = [[SBSessionData meta] findOne:@{ @"userKey": [user key] }];
            NSLog(@"session: %@", session);
            if (session) {
                user.session = self;
                user.authorized = YES;
                _sessionData = session;
                _user = user;
            }
        }
    }
    return self;
}

- (void)setPreferenceValue:(id)value forKey:(id<NSCopying>)key
{
    [self.sessionData setPrefValue:value forKey:key];
}

- (id)preferenceValueForKey:(id<NSCopying>)key
{
    return [self.sessionData.prefs objectForKey:key];
}

- (NSString *)identifier
{
    return _sessionData.key;
}

- (id)deserializeJSON:(id)JSON
{
    return JSON;
}

- (id (^)(SBModel *))objectDecorator
{
    static id (^ret) (SBModel *mod);
    if (!ret) {
        ret = ^ (SBModel *mod) {
            SBDataObject *obj = (SBDataObject *)mod;
            obj.session = self;
            obj.authorized = YES;
            return obj;
        };
    }
    return ret;
}

- (SBModelQueryBuilder *)queryBuilderForClass:(Class)modelCls
{
    return [[[[modelCls meta] queryBuilder] decorateResults:self.objectDecorator] property:@"userKey" isEqualTo:self.user.key];
}

- (SBModelQueryBuilder *)unsafeQueryBuilderForClass:(Class)modelCls
{
    return [[[[modelCls unsafeMeta] queryBuilder] decorateResults:self.objectDecorator] property:@"userKey" isEqualTo:self.user.key];
}

- (void)_configureHttpClient:(AFHTTPClient *)cli
{
    [cli registerHTTPOperationClass:[SBJSONRequestOperation class]];
}

- (AFHTTPClient *)anonymousHttpClient
{
    if (!_anonymousHttpClient) {
        NSURL *baseUrl = [NSURL URLWithString:[NSString stringWithFormat:self.apiMountPointSpec, self.apiVersion]];
        _anonymousHttpClient = [[SBHTTPClient alloc] initWithBaseURL:baseUrl];
        [self _configureHttpClient:_anonymousHttpClient];
    }
    return _anonymousHttpClient;
}

- (AFHTTPClient *)authorizedHttpClient
{
    if (!_authorizedHttpClient) {
        NSURL *baseUrl = [NSURL URLWithString:[NSString stringWithFormat:self.apiMountPointSpec, self.apiVersion]];
        NSString *apiKey = [[NSBundle mainBundle] objectForInfoDictionaryKey:SBApiIdKey];
        NSString *apiSecret = [[NSBundle mainBundle] objectForInfoDictionaryKey:SBApiSecretKey];
        _authorizedHttpClient = [[SBOAuth2Client alloc] initWithBaseURL:baseUrl clientID:apiKey secret:apiSecret];
    }
    if (self.apiCredential) {
        [_authorizedHttpClient setAuthorizationHeaderWithCredential:self.apiCredential];
    }
    return _authorizedHttpClient;
}

- (AFOAuthCredential *)apiCredential
{
    if (!self.identifier) {
        return nil;
    }
    if (!_apiCredential) {
        _apiCredential = [AFOAuthCredential retrieveCredentialWithIdentifier:self.identifier];
    }
    return _apiCredential;
}

- (void)setApiCredential:(AFOAuthCredential *)apiCredential
{
    _apiCredential = apiCredential;
    [_authorizedHttpClient setAuthorizationHeaderWithCredential:apiCredential];
}

- (void)logout
{
    [[self class] setLastUsedSession:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:SBLogoutNotification object:nil];
}

- (void)isEmailRegistered:(NSString *)email success:(SBSuccessBlock)success failure:(SBErrorBlock)failure
{
    NSMutableURLRequest *req = [self.anonymousHttpClient requestWithMethod:@"POST" path:@"check_email" parameters:@{ @"email": email }];
    AFHTTPRequestOperation *op = [self.anonymousHttpClient HTTPRequestOperationWithRequest:req success:^(AFHTTPRequestOperation *operation, id responseObject) {
        success([NSNumber numberWithBool:operation.response.statusCode == 200]);
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        if (operation.response.statusCode == 404) {
            success([NSNumber numberWithBool:NO]);
        } else {
            failure(error);
        }
    }];
    [self.anonymousHttpClient enqueueHTTPRequestOperation:op];
}

- (void)registerAndLoginUser:(SBUser *)user password:(NSString *)password success:(SBSuccessBlock)success failure:(SBErrorBlock)failure
{
    NSMutableDictionary *userData = [[user toNetworkRepresentation][@"user"] mutableCopy];
    [userData setObject:password forKey:@"password"];
    [userData setObject:password forKey:@"password_confirmation"];
    
    NSMutableURLRequest *req = [self.anonymousHttpClient requestWithMethod:@"POST"
                                                                      path:[user listPath]
                                                                parameters:@{ @"user": userData }];
    SBJSONRequestOperation *op = [[SBJSONRequestOperation alloc] initWithRequest:req];
    
//    [op setAuthenticationAgainstProtectionSpaceBlock:^BOOL(NSURLConnection *connection, NSURLProtectionSpace *protectionSpace) {
//        return YES;
//    }];
//    
//    [op setAuthenticationChallengeBlock:^(NSURLConnection *connection, NSURLAuthenticationChallenge *challenge) {
//        if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
//            [challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust] forAuthenticationChallenge:challenge];
//        }
//    }];
    
    [op setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSLog(@"successfully registered user - now attempting to get oauth");
        [user setValuesForKeysWithNetworkDictionary:responseObject];
        [user save];
        self.user = user;
        [self.sessionData save]; // make sure we have an identifier
        [self getOAuth:user password:password success:^ (id _) {
            self.sessionData.userKey = [user key];
            [self.sessionData save];
            [self syncPushToken];
            success(user);
        } failure:failure];
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"register failed to post user operation=%@ error=%@", operation, error);
        failure(error);
    }];
    [self.anonymousHttpClient enqueueHTTPRequestOperation:op];
}

- (void)anonymousJSONRequestWithMethod:(NSString *)method
                                  path:(NSString *)path
                            parameters:(NSDictionary *)params
                               success:(void (^)(NSURLRequest *, NSHTTPURLResponse *, id))success
                               failure:(void (^)(NSURLRequest *, NSHTTPURLResponse *, NSError *, id))failure
{
    [self.anonymousHttpClient setParameterEncoding:AFJSONParameterEncoding];
    NSURLRequest *req = [self.anonymousHttpClient requestWithMethod:method path:path parameters:params];
    SBJSONRequestOperation *op = [SBJSONRequestOperation JSONRequestOperationWithRequest:req success:
                                  ^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
                                      success(request, response, [self deserializeJSON:JSON]);
                                  } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
                                      failure(request, response, error, JSON);
                                  }];
    [self.anonymousHttpClient enqueueHTTPRequestOperation:op];
}

- (void)authorizedJSONRequestWithRequestBlock:(NSURLRequest *(^)(void))requestBlock
                                      success:(void (^)(NSURLRequest *, NSHTTPURLResponse *, id))success
                                      failure:(void (^)(NSURLRequest *, NSHTTPURLResponse *, NSError *, id))failure
{
    NSURLRequest *req = requestBlock();
    SBJSONRequestOperation *op = [SBJSONRequestOperation JSONRequestOperationWithRequest:req success:
      ^(NSURLRequest *req, NSHTTPURLResponse *resp, id JSON) {
          success(req, resp, [self deserializeJSON:JSON]);
      } failure:
      ^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
          if (response.statusCode == 401) {
              // attempt to re-up the auth token using the refresh token against a 401
              [self.authorizedHttpClient authenticateUsingOAuthWithPath:@"/oauth2/token" refreshToken:self.apiCredential.refreshToken success:^(AFOAuthCredential *credential) {
                  NSLog(@"got re-auth using refreshToken %@ %@", self.apiCredential.refreshToken, request.URL);
                  
                  NSParameterAssert(self.identifier != nil); // TODO: remove in production
                  NSLog(@"previous token: %@", self.apiCredential);
                  [AFOAuthCredential storeCredential:credential withIdentifier:self.identifier];
                  self.apiCredential = credential;
                  NSLog(@"new token: %@", self.apiCredential);
                  
                  // retry but don't attach the redirect handler so we don't have an infinite retry loop
                  NSURLRequest *retryReq = requestBlock();
                  SBJSONRequestOperation *retry = [SBJSONRequestOperation JSONRequestOperationWithRequest:retryReq success:success failure:failure];
                  [self.authorizedHttpClient enqueueHTTPRequestOperation:retry];
              } failure:^(NSError *error) {
                  NSLog(@"failed to re-auth: %@", error);
                  [self.class setLastUsedSession:nil];
                  [[NSNotificationCenter defaultCenter] postNotificationName:SBLoginDidBecomeInvalidNotification object:nil];
                  failure(nil, nil, error, nil);
              }];
          } else {
              if (JSON && JSON[@"error"]) {
                  NSDictionary *d = @{NSLocalizedDescriptionKey: JSON[@"error"],
                                      NSUnderlyingErrorKey: error};
                  error = [[NSError alloc] initWithDomain:AFNetworkingErrorDomain code:error.code userInfo:d];
              }
              failure(request, response, error, JSON);
          }
      }];
    [op setRedirectResponseBlock:^NSURLRequest *(NSURLConnection *connection, NSURLRequest *request, NSURLResponse *redirectResponse) {
        if (redirectResponse) {
            NSString *url = [request.URL description];
            NSRange signInRange = [url rangeOfString:@"/users/sign_in" options:0];
            if (signInRange.location != NSNotFound && signInRange.location + signInRange.length == url.length) {
                // our access token likely expired, try to re-authenticate with the refresh token
                [self.authorizedHttpClient authenticateUsingOAuthWithPath:@"/oauth2/token" refreshToken:self.apiCredential.refreshToken success:^(AFOAuthCredential *credential) {
                    NSLog(@"got re-auth using refreshToken %@ %@", self.apiCredential.refreshToken, request.URL);
                    
                    NSParameterAssert(self.identifier != nil); // TODO: remove in production
                    NSLog(@"previous token: %@", self.apiCredential);
                    [AFOAuthCredential storeCredential:credential withIdentifier:self.identifier];
                    self.apiCredential = credential;
                    NSLog(@"new token: %@", self.apiCredential);
                    
                    // retry but don't attach the redirect handler so we don't have an infinite retry loop
                    NSURLRequest *retryReq = requestBlock();
                    SBJSONRequestOperation *retry = [SBJSONRequestOperation JSONRequestOperationWithRequest:retryReq success:success failure:failure];
                    [self.authorizedHttpClient enqueueHTTPRequestOperation:retry];
                } failure:^(NSError *error) {
                    NSLog(@"failed to re-auth: %@", error);
                    [self.class setLastUsedSession:nil];
                    [[NSNotificationCenter defaultCenter] postNotificationName:SBLoginDidBecomeInvalidNotification object:nil];
                    failure(nil, nil, error, nil);
                }];
                return nil;
            }
        }
        return request;
    }];
    [self.authorizedHttpClient enqueueHTTPRequestOperation:op];
}

- (void)authorizedJSONRequestWithMethod:(NSString *)method path:(NSString *)path paramters:(NSDictionary *)params
                      success:(void(^)(NSURLRequest *request, NSHTTPURLResponse *response, id json))success
                      failure:(void(^)(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id json))failure
{
    NSURLRequest * (^block)(void) = ^ {
        [self.authorizedHttpClient setParameterEncoding:AFJSONParameterEncoding];
        return [self.authorizedHttpClient requestWithMethod:method path:path parameters:params];
    };
    return [self authorizedJSONRequestWithRequestBlock:block success:success failure:failure];
}

- (void)loginWithEmail:(NSString *)email password:(NSString *)password success:(SBSuccessBlock)success failure:(SBErrorBlock)failure
{
    if (!self.user) {
        self.user = [[_userClass alloc] initWithSession:self];
        self.user.email = email;
    }
    [self.sessionData save]; // generate an identifier for this session
    [self getOAuth:self.user password:password success:^(id _) {
        // now that we've got oauth, get the user data
        NSMutableURLRequest *req = [self.authorizedHttpClient requestWithMethod:@"GET" path:[self.user listPath] parameters:@{ }];
        [req addValue:@"application/json" forHTTPHeaderField:@"Accept"];
        SBJSONRequestOperation *op = [[SBJSONRequestOperation alloc] initWithRequest:req];
        [op setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
            [self.user setValuesForKeysWithNetworkDictionary:responseObject];
            [self.user save];
            self.sessionData.userKey = self.user.key;
            [self.sessionData save];
            [self syncPushToken];
            success(self.user);
        } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
            NSLog(@"operation: %@", operation.request.allHTTPHeaderFields);
            failure(error);
        }];
        [self.authorizedHttpClient enqueueHTTPRequestOperation:op];
    } failure:^(NSError *err) {
        failure(err);
    }];
}

- (void)getOAuth:(SBUser *)user password:(NSString *)password success:(SBSuccessBlock)success failure:(SBErrorBlock)failure
{
    [self.authorizedHttpClient authenticateUsingOAuthWithPath:@"/oauth2/token" username:user.email
                                                     password:password scope:nil success:
     ^(AFOAuthCredential *credential) {
         [AFOAuthCredential storeCredential:credential withIdentifier:self.identifier];
         success(user);
     } failure:^(NSError *error) {
         NSLog(@"oauth crapped %@", error);
         NSError *dumbError = [NSError errorWithDomain:@"" code:400 userInfo:
                               @{ NSUnderlyingErrorKey: error,
                                  NSLocalizedDescriptionKey: NSLocalizedString(@"Invalid password", nil) }];
         failure(dumbError);
     }];
}

- (void)syncUser
{
    [self syncUserSuccess:^(id successObj) {
        //
    } failure:^(NSError *error) {
        //
    }];
}

- (void)syncUserSuccess:(SBSuccessBlock)success failure:(SBErrorBlock)failure
{
    [self authorizedJSONRequestWithMethod:@"GET" path:@"/users.json" paramters:@{} success:
     ^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, id JSON) {
         [self.user setValuesForKeysWithNetworkDictionary:JSON];
         dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
             [self.user save];
             success(self.user);
             NSLog(@"successfully got and saved user");
//             [self syncPushToken];
         });
     } failure:^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, NSError *error, id JSON) {
         NSLog(@"failed to get current user error=%@ json=%@", error, JSON);
         failure(error);
     }];
}

- (void)syncPushToken
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didGetPushNotificationToken:) name:SBDidReceiveRemoteNotificationAuthorization object:nil];
    [[UIApplication sharedApplication] registerForRemoteNotificationTypes:(UIRemoteNotificationTypeAlert | UIRemoteNotificationTypeBadge | UIRemoteNotificationTypeSound)];
}

- (void)didGetPushNotificationToken:(NSNotification *)note
{
    NSString *token = note.userInfo[@"pushToken"];
    NSString *udid = [SecureUDID UDIDForDomain:@"SBData" usingKey:@"__CHANGEME__"];
#ifdef DEBUG
    NSString *environment = @"sandbox";
#else
    NSString *environment = @"production";
#endif
    NSDictionary *resource = @{ @"device_id": udid, @"token": token, @"type": @"push_device", @"device_type": @"apns", @"environment": environment };

    [self authorizedJSONRequestWithMethod:@"POST" path:@"push_devices" paramters:resource success:^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, id JSON) {
        NSLog(@"successfully saved push token: %@", JSON);
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, NSError *error, id JSON) {
        NSLog(@"failed to get push token error=%@ json=%@", error, JSON);
    }];
}

@end
