//
//  RNFSManager.h
//  RNFSManager
//
//  Created by Johannes Lumpe on 08/05/15.
//  Copyright (c) 2015 Johannes Lumpe. All rights reserved.
//

#import <React/RCTBridgeModule.h>
#import <React/RCTLog.h>

typedef void (^completionHandler)();

@interface RNFSManager : NSObject <RCTBridgeModule>

+ (void) setCompletionHandler:(completionHandler)handler forSessionId:(NSString*) sessionId;
+ (completionHandler) getCompletionHandlerForSessionId:(NSString*)sessionId;
+ (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session;
+ (void) setErrorDomain:(NSString *)domain;
+ (NSString *) getErrorDomain;

@end
