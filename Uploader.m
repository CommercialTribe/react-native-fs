#import "Uploader.h"
#import "RNFSManager.h"

@implementation RNFSUploadParams

@end

@interface RNFSUploader()

@property (copy) RNFSUploadParams* params;

@property (retain) NSURLSessionDataTask* task;
@property (retain) NSMutableDictionary* responseData;

@end

@implementation RNFSUploader

- (void)uploadFiles:(RNFSUploadParams*)params
{
  _params = params;
  _responseData = [[NSMutableDictionary alloc] init];
  NSString *method = _params.method;
  NSURL *url = [NSURL URLWithString:_params.toUrl];
  NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
  [req setHTTPMethod:method];

  // set headers
  for (NSString *key in _params.headers) {
    id val = [_params.headers objectForKey:key];
    if ([val respondsToSelector:@selector(stringValue)]) {
      val = [val stringValue];
    }
    if (![val isKindOfClass:[NSString class]]) {
      continue;
    }
    [req setValue:val forHTTPHeaderField:key];
  }
  
  if (_params.background) {
    NSLog(@"---CREATING BACKGROUND TASK---");
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDictionary *file = [_params.files objectAtIndex:0];
    NSString *filepath = file[@"filepath"];
    NSError* error = [self validateFilePath:filepath withFileManager:fileManager];
    if(error != nil){
      return _params.errorCallback(error);
    }
    _task = [self createBackgroundUploadTaskFromReq:req fromFilePath:filepath];
  }
  else{
    NSLog(@"---CREATING FOREGROUND TASK---");
    NSString *formBoundaryString = [self generateBoundaryString];
    NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", formBoundaryString];
    [req setValue:contentType forHTTPHeaderField:@"Content-Type"];
      
    NSData *formBoundaryData = [[NSString stringWithFormat:@"--%@\r\n", formBoundaryString] dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData* reqBody = [NSMutableData data];
    [self setBodyFormFields:reqBody withBoundaryData:formBoundaryData];
    NSError* error = [self setBodyFiles:reqBody withBoundaryData:formBoundaryData];
    if(error != nil){
      return _params.errorCallback(error);
    }
    NSData* end = [[NSString stringWithFormat:@"--%@--\r\n", formBoundaryString] dataUsingEncoding:NSUTF8StringEncoding];
    [reqBody appendData:end];
    [req setHTTPBody:reqBody];
    _task = [self createUploadTaskFromReq:req];
  }
  
  [_task resume];
  _params.beginCallback();
}

- (void)stopUpload
{
    [_task cancel];
}

- (void)setBodyFormFields:(NSMutableData *)reqBody withBoundaryData:(NSData *)formBoundaryData
{
  for (NSString *key in _params.fields) {
    id val = [_params.fields objectForKey:key];
    if ([val respondsToSelector:@selector(stringValue)]) {
      val = [val stringValue];
    }
    if (![val isKindOfClass:[NSString class]]) {
      continue;
    }
    
    [reqBody appendData:formBoundaryData];
    [reqBody appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", key] dataUsingEncoding:NSUTF8StringEncoding]];
    [reqBody appendData:[val dataUsingEncoding:NSUTF8StringEncoding]];
    [reqBody appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
  }
}

- (NSError *)setBodyFiles:(NSMutableData *)reqBody withBoundaryData:(NSData *)formBoundaryData
{
  NSFileManager *fileManager = [NSFileManager defaultManager];
  for (NSDictionary *file in _params.files) {
    NSString *name = file[@"name"];
    NSString *filename = file[@"filename"];
    NSString *filepath = file[@"filepath"];
    NSString *filetype = file[@"filetype"];
      
    NSError* error = [self validateFilePath:filepath withFileManager:fileManager];
    if(error != nil){
      return error;
    }
      
    [reqBody appendData:formBoundaryData];
    [reqBody appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n", name.length ? name : filename, filename] dataUsingEncoding:NSUTF8StringEncoding]];
    
    if (filetype) {
      [reqBody appendData:[[NSString stringWithFormat:@"Content-Type: %@\r\n", filetype] dataUsingEncoding:NSUTF8StringEncoding]];
    } else {
      [reqBody appendData:[[NSString stringWithFormat:@"Content-Type: %@\r\n", [self mimeTypeForPath:filename]] dataUsingEncoding:NSUTF8StringEncoding]];
    }
    NSData *fileData = [NSData dataWithContentsOfFile:filepath];
    [reqBody appendData:[[NSString stringWithFormat:@"Content-Length: %ld\r\n\r\n", (long)[fileData length]] dataUsingEncoding:NSUTF8StringEncoding]];
    [reqBody appendData:fileData];
    [reqBody appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
  }
    
  return nil;
}

- (NSURLSessionDataTask *)createUploadTaskFromReq: (NSMutableURLRequest *)req
{
    NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfiguration delegate:(id)self delegateQueue:[NSOperationQueue mainQueue]];
    return [session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
      NSLog(@"---INLINE COMPLETED EMIT---");
      NSString * str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
      return _params.completeCallback(str, response);
    }];
}

- (NSURLSessionDataTask *)createBackgroundUploadTaskFromReq: (NSMutableURLRequest *)req fromFilePath:(NSString *)filepath
{
    NSURL *fileUrl = [NSURL fileURLWithPath:filepath];
    NSString *uuid = [[NSUUID UUID] UUIDString];
    NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:uuid];
    sessionConfiguration.sessionSendsLaunchEvents = YES;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfiguration delegate:(id)self delegateQueue:[NSOperationQueue mainQueue]];
    return [session uploadTaskWithRequest:req fromFile:fileUrl];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
  NSLog(@"---COMPLETED EMIT---");
  if(error != nil) {
    return _params.errorCallback(error);
  }
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)task.response;
    NSMutableData *responseForTask = [_responseData objectForKey:@(task.taskIdentifier)];
    NSString *body = @"";
    if (responseForTask) {
        body = [[NSString alloc] initWithData:responseForTask encoding:NSUTF8StringEncoding];
        NSLog(@"---WITH DATA---");
        [_responseData removeObjectForKey:@(task.taskIdentifier)];
    }
   return _params.completeCallback(body, httpResponse);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didSendBodyData:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend
{
  NSLog(@"---PROGRESS EMIT---");
  return _params.progressCallback([NSNumber numberWithLongLong:totalBytesExpectedToSend], [NSNumber numberWithLongLong:totalBytesSent]);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    NSLog(@"---RECEIVED DATA---");
    NSMutableData *responseData = [_responseData objectForKey:@(dataTask.taskIdentifier)];
    if (!responseData) {
        responseData = [NSMutableData dataWithData:data];
        [_responseData setObject:responseData forKey:@(dataTask.taskIdentifier)];
    } else {
        [responseData appendData:data];
    }
}

- (NSError *)validateFilePath:(NSString *)filepath withFileManager:(NSFileManager*)fileManager
{
    if (![fileManager fileExistsAtPath:filepath]){
        NSLog(@"Failed to open target file at path: %@", filepath);
        NSError* error = [NSError errorWithDomain:@"Uploader" code:NSURLErrorFileDoesNotExist userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat: @"Failed to open target file at path: %@", filepath]}];
        return error;
    }
    return nil;
}

- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session
{
    NSLog(@"URLSessionDidFinishEventsForBackgroundURLSession");
    
    completionHandler sessionCompletionHandler = [RNFSManager getCompletionHandler];
    if (sessionCompletionHandler) {
        [RNFSManager setCompletionHandler:nil];
        sessionCompletionHandler();
    }
}

- (NSString *)generateBoundaryString
{
  NSString *uuid = [[NSUUID UUID] UUIDString];
  return [NSString stringWithFormat:@"----%@", uuid];
}

- (NSString *)mimeTypeForPath:(NSString *)filepath
{
  NSString *fileExtension = [filepath pathExtension];
  NSString *UTI = (__bridge_transfer NSString *)UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)fileExtension, NULL);
  NSString *contentType = (__bridge_transfer NSString *)UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)UTI, kUTTagClassMIMEType);
    
  if (contentType) {
    return contentType;
  }
  return @"application/octet-stream";
}
@end
