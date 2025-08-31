#import "VoiceVosk.h"
#import <React/RCTLog.h>
#import <React/RCTUtils.h>
#import <AVFoundation/AVFoundation.h>
#import <vosk/vosk_api.h>

@interface VoiceVosk ()

@property (nonatomic) VoskModel *model;
@property (nonatomic) VoskRecognizer *recognizer;
@property (nonatomic) AVAudioEngine *audioEngine;
@property (nonatomic) AVAudioInputNode *inputNode;
@property (nonatomic, assign) BOOL isModelInitialized;
@property (nonatomic, assign) BOOL isListening;
@property (nonatomic, assign) float sampleRate;
@property (nonatomic, assign) BOOL speechStartDetected;
@property (nonatomic, strong) NSString *lastPartialResult;
@property (nonatomic, strong) dispatch_queue_t processingQueue;

@end

@implementation VoiceVosk

RCT_EXPORT_MODULE(VoiceVosk);

+ (BOOL)requiresMainQueueSetup {
    return NO;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _sampleRate = 16000.0f;
        _isModelInitialized = NO;
        _isListening = NO;
        _speechStartDetected = NO;
        _processingQueue = dispatch_queue_create("com.voicevosk.processing", DISPATCH_QUEUE_SERIAL);
        
        // Initialize Vosk logging
        vosk_set_log_level(0); // 0 = INFO level
    }
    return self;
}

- (NSArray<NSString *> *)supportedEvents {
    return @[@"onResult", @"onFinalResult", @"onPartialResult", @"onError", @"onTimeout", @"onSpeechStart", @"onSpeechEnd"];
}

#pragma mark - Model Management

RCT_EXPORT_METHOD(initModel:(NSDictionary *)config
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    
    dispatch_async(_processingQueue, ^{
        @try {
            NSString *modelPath = config[@"modelPath"];
            if (!modelPath || modelPath.length == 0) {
                reject(@"INVALID_MODEL_PATH", @"Model path cannot be null or empty", nil);
                return;
            }
            
            if (config[@"sampleRate"]) {
                self.sampleRate = [config[@"sampleRate"] floatValue];
            }
            
            // Clean up existing model
            [self cleanupModel];
            
            // Check if model exists at path
            NSFileManager *fileManager = [NSFileManager defaultManager];
            if (![fileManager fileExistsAtPath:modelPath]) {
                reject(@"MODEL_NOT_FOUND", [NSString stringWithFormat:@"Model not found at path: %@", modelPath], nil);
                return;
            }
            
            // Load model
            self.model = vosk_model_new([modelPath UTF8String]);
            if (!self.model) {
                reject(@"MODEL_LOAD_FAILED", @"Failed to load Vosk model", nil);
                return;
            }
            
            // Create recognizer
            NSString *grammar = config[@"grammar"];
            if (grammar && grammar.length > 0) {
                self.recognizer = vosk_recognizer_new_grm(self.model, self.sampleRate, [grammar UTF8String]);
            } else {
                self.recognizer = vosk_recognizer_new(self.model, self.sampleRate);
            }
            
            if (!self.recognizer) {
                vosk_model_free(self.model);
                self.model = NULL;
                reject(@"RECOGNIZER_INIT_FAILED", @"Failed to initialize recognizer", nil);
                return;
            }
            
            self.isModelInitialized = YES;
            resolve(@YES);
            RCTLogInfo(@"Vosk model initialized successfully");
            
        } @catch (NSException *exception) {
            [self cleanupModel];
            reject(@"INIT_ERROR", [NSString stringWithFormat:@"Error initializing model: %@", exception.reason], nil);
        }
    });
}

RCT_EXPORT_METHOD(isModelInitialized:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(@(self.isModelInitialized));
}

RCT_EXPORT_METHOD(releaseModel:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    
    dispatch_async(_processingQueue, ^{
        @try {
            [self stopListeningInternal];
            [self cleanupModel];
            resolve(@YES);
            RCTLogInfo(@"Vosk model released");
        } @catch (NSException *exception) {
            reject(@"RELEASE_ERROR", [NSString stringWithFormat:@"Error releasing model: %@", exception.reason], nil);
        }
    });
}

#pragma mark - Recognition Control

RCT_EXPORT_METHOD(startListening:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    
    if (!self.isModelInitialized) {
        reject(@"MODEL_NOT_INITIALIZED", @"Model is not initialized", nil);
        return;
    }
    
    // Check microphone permission
    AVAudioSession *session = [AVAudioSession sharedInstance];
    if ([session recordPermission] != AVAudioSessionRecordPermissionGranted) {
        reject(@"PERMISSION_DENIED", @"Microphone permission not granted", nil);
        return;
    }
    
    dispatch_async(_processingQueue, ^{
        @try {
            [self stopListeningInternal];
            
            // Setup audio session
            AVAudioSession *audioSession = [AVAudioSession sharedInstance];
            NSError *error;
            
            [audioSession setCategory:AVAudioSessionCategoryRecord
                          withOptions:AVAudioSessionCategoryOptionMixWithOthers
                                error:&error];
            if (error) {
                reject(@"AUDIO_SESSION_ERROR", error.localizedDescription, error);
                return;
            }
            
            [audioSession setActive:YES error:&error];
            if (error) {
                reject(@"AUDIO_SESSION_ERROR", error.localizedDescription, error);
                return;
            }
            
            // Setup audio engine
            self.audioEngine = [[AVAudioEngine alloc] init];
            self.inputNode = [self.audioEngine inputNode];
            
            AVAudioFormat *recordingFormat = [self.inputNode outputFormatForBus:0];
            AVAudioFormat *format = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16
                                                                      sampleRate:self.sampleRate
                                                                        channels:1
                                                                     interleaved:YES];
            
            AVAudioConverter *converter = [[AVAudioConverter alloc] initFromFormat:recordingFormat toFormat:format];
            
            [self.inputNode installTapOnBus:0
                                 bufferSize:1024
                                     format:recordingFormat
                                      block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
                [self processAudioBuffer:buffer withConverter:converter];
            }];
            
            [self.audioEngine startAndReturnError:&error];
            if (error) {
                reject(@"AUDIO_ENGINE_ERROR", error.localizedDescription, error);
                return;
            }
            
            // Reset speech detection state
            self.speechStartDetected = NO;
            self.lastPartialResult = nil;
            
            self.isListening = YES;
            resolve(@YES);
            RCTLogInfo(@"Started listening");
            
        } @catch (NSException *exception) {
            reject(@"START_LISTENING_ERROR", exception.reason, nil);
        }
    });
}

RCT_EXPORT_METHOD(stopListening:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    
    dispatch_async(_processingQueue, ^{
        @try {
            [self stopListeningInternal];
            resolve(@YES);
            RCTLogInfo(@"Stopped listening");
        } @catch (NSException *exception) {
            reject(@"STOP_LISTENING_ERROR", exception.reason, nil);
        }
    });
}

RCT_EXPORT_METHOD(setPause:(BOOL)paused
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    
    dispatch_async(_processingQueue, ^{
        @try {
            if (self.audioEngine) {
                if (paused) {
                    [self.audioEngine pause];
                } else {
                    NSError *error;
                    [self.audioEngine startAndReturnError:&error];
                    if (error) {
                        reject(@"PAUSE_ERROR", error.localizedDescription, error);
                        return;
                    }
                }
                resolve(@YES);
                RCTLogInfo(@"Speech recognition %@", paused ? @"paused" : @"resumed");
            } else {
                reject(@"SERVICE_NOT_ACTIVE", @"Audio engine is not active", nil);
            }
        } @catch (NSException *exception) {
            reject(@"PAUSE_ERROR", exception.reason, nil);
        }
    });
}

RCT_EXPORT_METHOD(isListening:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(@(self.isListening));
}

#pragma mark - File Recognition

RCT_EXPORT_METHOD(recognizeFile:(NSString *)filePath
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    
    if (!self.isModelInitialized) {
        reject(@"MODEL_NOT_INITIALIZED", @"Model is not initialized", nil);
        return;
    }
    
    dispatch_async(_processingQueue, ^{
        @try {
            NSFileManager *fileManager = [NSFileManager defaultManager];
            if (![fileManager fileExistsAtPath:filePath]) {
                reject(@"FILE_NOT_FOUND", [NSString stringWithFormat:@"Audio file not found: %@", filePath], nil);
                return;
            }
            
            NSURL *fileURL = [NSURL fileURLWithPath:filePath];
            NSError *error;
            AVAudioFile *audioFile = [[AVAudioFile alloc] initForReading:fileURL error:&error];
            
            if (error) {
                reject(@"INVALID_FILE", error.localizedDescription, error);
                return;
            }
            
            AVAudioFormat *processingFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16
                                                                               sampleRate:self.sampleRate
                                                                                 channels:1
                                                                              interleaved:YES];
            
            AVAudioConverter *converter = [[AVAudioConverter alloc] initFromFormat:audioFile.processingFormat
                                                                          toFormat:processingFormat];
            
            AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:audioFile.processingFormat
                                                                      frameCapacity:(AVAudioFrameCount)audioFile.length];
            
            [audioFile readIntoBuffer:buffer error:&error];
            if (error) {
                reject(@"FILE_READ_ERROR", error.localizedDescription, error);
                return;
            }
            
            [self processFileBuffer:buffer withConverter:converter];
            
            resolve(@YES);
            RCTLogInfo(@"Started file recognition: %@", filePath);
            
        } @catch (NSException *exception) {
            reject(@"FILE_RECOGNITION_ERROR", exception.reason, nil);
        }
    });
}

RCT_EXPORT_METHOD(stopFileRecognition:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    
    dispatch_async(_processingQueue, ^{
        @try {
            // File recognition is synchronous in this implementation
            resolve(@YES);
            RCTLogInfo(@"Stopped file recognition");
        } @catch (NSException *exception) {
            reject(@"STOP_FILE_ERROR", exception.reason, nil);
        }
    });
}

#pragma mark - Utility Methods

RCT_EXPORT_METHOD(isRecognitionAvailable:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    BOOL available = [session isInputAvailable];
    resolve(@(available));
}

RCT_EXPORT_METHOD(getSampleRate:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(@(self.sampleRate));
}

#pragma mark - Private Methods

- (void)cleanupModel {
    if (self.recognizer) {
        vosk_recognizer_free(self.recognizer);
        self.recognizer = NULL;
    }
    if (self.model) {
        vosk_model_free(self.model);
        self.model = NULL;
    }
    self.isModelInitialized = NO;
}

- (void)stopListeningInternal {
    if (self.audioEngine) {
        [self.inputNode removeTapOnBus:0];
        [self.audioEngine stop];
        self.audioEngine = nil;
        self.inputNode = nil;
    }
    
    [[AVAudioSession sharedInstance] setActive:NO error:nil];
    
    self.isListening = NO;
    self.speechStartDetected = NO;
    self.lastPartialResult = nil;
}

- (void)processAudioBuffer:(AVAudioPCMBuffer *)buffer withConverter:(AVAudioConverter *)converter {
    if (!self.recognizer || !buffer) return;
    
    AVAudioPCMBuffer *convertedBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:converter.outputFormat
                                                                       frameCapacity:buffer.frameCapacity];
    
    NSError *error;
    AVAudioConverterInputStatus status = [converter convertToBuffer:convertedBuffer
                                                               error:&error
                                                  withInputFromBlock:^AVAudioBuffer *(AVAudioPacketCount inNumberOfPackets, AVAudioConverterInputStatus *outStatus) {
        *outStatus = AVAudioConverterInputStatus_HaveData;
        return buffer;
    }];
    
    if (status != AVAudioConverterInputStatus_HaveData || error) {
        return;
    }
    
    int16_t *audioData = (int16_t *)convertedBuffer.int16ChannelData[0];
    AVAudioFrameCount frameCount = convertedBuffer.frameLength;
    
    if (vosk_recognizer_accept_waveform(self.recognizer, audioData, (int)(frameCount * sizeof(int16_t)))) {
        const char *result = vosk_recognizer_result(self.recognizer);
        if (result) {
            [self handleResult:[NSString stringWithUTF8String:result]];
        }
    } else {
        const char *partialResult = vosk_recognizer_partial_result(self.recognizer);
        if (partialResult) {
            [self handlePartialResult:[NSString stringWithUTF8String:partialResult]];
        }
    }
}

- (void)processFileBuffer:(AVAudioPCMBuffer *)buffer withConverter:(AVAudioConverter *)converter {
    if (!self.recognizer || !buffer) return;
    
    AVAudioPCMBuffer *convertedBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:converter.outputFormat
                                                                       frameCapacity:buffer.frameCapacity];
    
    NSError *error;
    AVAudioConverterInputStatus status = [converter convertToBuffer:convertedBuffer
                                                               error:&error
                                                  withInputFromBlock:^AVAudioBuffer *(AVAudioPacketCount inNumberOfPackets, AVAudioConverterInputStatus *outStatus) {
        *outStatus = AVAudioConverterInputStatus_HaveData;
        return buffer;
    }];
    
    if (status != AVAudioConverterInputStatus_HaveData || error) {
        return;
    }
    
    int16_t *audioData = (int16_t *)convertedBuffer.int16ChannelData[0];
    AVAudioFrameCount frameCount = convertedBuffer.frameLength;
    
    vosk_recognizer_accept_waveform(self.recognizer, audioData, (int)(frameCount * sizeof(int16_t)));
    
    const char *finalResult = vosk_recognizer_final_result(self.recognizer);
    if (finalResult) {
        [self handleFinalResult:[NSString stringWithUTF8String:finalResult]];
    }
}

- (void)handleResult:(NSString *)result {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *parsedResult = [self parseJSONString:result];
        NSString *text = parsedResult[@"text"] ?: @"";
        
        RCTLogInfo(@"onResult: %@", text);
        [self sendEventWithName:@"onResult" body:@{@"text": text}];
    });
}

- (void)handleFinalResult:(NSString *)result {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *parsedResult = [self parseJSONString:result];
        NSString *text = parsedResult[@"text"] ?: @"";
        
        RCTLogInfo(@"onFinalResult: %@", text);
        [self sendEventWithName:@"onFinalResult" body:@{@"text": text}];
    });
}

- (void)handlePartialResult:(NSString *)result {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *parsedResult = [self parseJSONString:result];
        NSString *partial = parsedResult[@"partial"] ?: @"";
        
        // Detect speech start and end
        [self detectSpeechStart:partial];
        [self detectSpeechEnd:partial];
        
        RCTLogInfo(@"onPartialResult: %@", partial);
        [self sendEventWithName:@"onPartialResult" body:@{@"partial": partial}];
    });
}

- (void)detectSpeechStart:(NSString *)partialResult {
    if (!self.speechStartDetected && partialResult.length > 0) {
        self.speechStartDetected = YES;
        RCTLogInfo(@"Speech start detected");
        [self sendEventWithName:@"onSpeechStart" body:nil];
    }
}

- (void)detectSpeechEnd:(NSString *)partialResult {
    if (self.speechStartDetected && partialResult.length == 0 && self.lastPartialResult.length > 0) {
        self.speechStartDetected = NO;
        RCTLogInfo(@"Speech end detected");
        [self sendEventWithName:@"onSpeechEnd" body:nil];
    }
    self.lastPartialResult = partialResult;
}

- (NSDictionary *)parseJSONString:(NSString *)jsonString {
    if (!jsonString) return @{};
    
    NSData *data = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    
    if (error || ![json isKindOfClass:[NSDictionary class]]) {
        return @{};
    }
    
    return json;
}

- (void)dealloc {
    [self stopListeningInternal];
    [self cleanupModel];
}

@end