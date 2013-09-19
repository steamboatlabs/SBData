//
// SBSession.h
//  SBData
//
//  Created by Samuel Sutch on 2/11/13.
//  Copyright (c) Steamboat Labs. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SBModel.h"

#define SBApiBaseURLKey @"SBAPIBaseURLSpec"
#define SBApiVersionKey @"SBAPIVersion"
#define SBApiIdKey @"SBApiClientId"
#define SBApiSecretKey @"SBApiSecret"
#define SBApiAllowUntrustedCertificateKey @"SBAPIAllowInvalidSSLCertificate"

typedef void(^SBSuccessBlock)(id successObj);
typedef void(^SBErrorBlock)(NSError *error);

extern NSString *SBLoginDidBecomeInvalidNotification; // for when the authentication becomes invalid
extern NSString *SBLogoutNotification; // for when user logs out
extern NSString *SBDidReceiveRemoteNotification;
extern NSString *SBDidReceiveRemoteNotificationAuthorization;

@class SBUser;
@class AFHTTPClient;
@class AFOAuth2Client;
@class AFOAuthCredential;
@class SBDataObject;

@interface SBSessionData : SBModel

@property (nonatomic) NSString *userKey;
@property (nonatomic) NSString *s3UploadPrefix;
@property (nonatomic) NSString *s3Bucket;
@property (nonatomic) NSDictionary *prefs;

- (void)setPrefValue:(id)val forKey:(id<NSCopying>)key;

@end


@interface SBSession : NSObject

@property (nonatomic, readonly) SBUser *user;
@property (nonatomic, readonly) AFOAuthCredential *apiCredential;
@property (nonatomic, readonly) NSString *apiMountPointSpec;
@property (nonatomic, readonly) NSString *apiVersion;

@property (nonatomic, readonly) AFHTTPClient *anonymousHttpClient;
@property (nonatomic, readonly) AFOAuth2Client *authorizedHttpClient;

@property (nonatomic, readonly) NSString *identifier;

//- (id)initWithEmailAddress:(NSString *)email;
+ (instancetype)sessionWithEmailAddress:(NSString *)email userClass:(Class)klass;

+ (void)setLastUsedSession:(SBSession *)session;
+ (instancetype)lastUsedSessionWithUserClass:(Class)userClass;

- (void)setPreferenceValue:(id)value forKey:(id<NSCopying>)key;
- (id)preferenceValueForKey:(id<NSCopying>)key;

- (id(^)(SBModel *))objectDecorator;
- (SBModelQueryBuilder *)queryBuilderForClass:(Class)modelCls; // a query builder which preconfigures the decorator and userKey parameter
- (SBModelQueryBuilder *)unsafeQueryBuilderForClass:(Class)modelCls;

// LOGIN AND REGISTRATION ----------------------------------------------------------------------------------------------

// both login and register methods:
// success returns:SBUser
//
// also sets SBSession currentSession] to this session
//
// also saves the oauth credentials to the keychain and caches the user

- (void)loginWithEmail:(NSString *)email password:(NSString *)password
               success:(SBSuccessBlock)success failure:(SBErrorBlock)fail;

- (void)logout;

- (void)registerAndLoginUser:(SBUser *)user password:(NSString *)password
                     success:(SBSuccessBlock)success failure:(SBErrorBlock)failure;

// send an authorized JSON request, retrying on auth errors to try and re-acquire a valid request token
// requestBlock() is called to generate an NSURLRequest, potentially multiple times
- (void)authorizedJSONRequestWithRequestBlock:(NSURLRequest * (^)(void))requestBlock
                                      success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *httpResponse, id JSON))success
                                      failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *httpResponse, NSError *error, id JSON))failure;

// convenience method that calls the above method 
- (void)authorizedJSONRequestWithMethod:(NSString *)method path:(NSString *)path paramters:(NSDictionary *)params
                                success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *httpResponse, id JSON))success
                                failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *httpResponse, NSError *error, id JSON))failure;

// success: NSNumber - bool
- (void)isEmailRegistered:(NSString *)email success:(SBSuccessBlock)success failure:(SBErrorBlock)failure;

// updates self.user with an updated copy from the web
- (void)syncUser;

// asks for permission to send push notifications and subsequently uploads the push notification token for this device id
- (void)syncPushToken;

@end
