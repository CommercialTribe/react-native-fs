//
//  RNFSManager.h
//  RNFSManager
//
//  Created by Johannes Lumpe on 08/05/15.
//  Copyright (c) 2015 Johannes Lumpe. All rights reserved.
//

#import "RCTBridgeModule.h"
#import "RCTLog.h"

typedef void (^completionHandler)();

@interface RNFSManager : NSObject <RCTBridgeModule>

+ (void) setCompletionHandler:(completionHandler)handler forSessionId:(NSString*) sessionId;
+ (completionHandler) getCompletionHandlerForSessionId:(NSString*)sessionId;
+ (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session;

@end
