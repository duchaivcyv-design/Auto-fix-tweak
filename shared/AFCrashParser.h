#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

NS_ASSUME_NONNULL_BEGIN

@interface AFCrashInfo : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic) NSTimeInterval time;
@property (nonatomic, copy) NSString *procName;
@property (nonatomic, copy, nullable) NSString *exceptionType;
@property (nonatomic, copy, nullable) NSString *terminationReason;
@property (nonatomic, copy, nullable) NSString *suspectBase;
@property (nonatomic, copy, nullable) NSString *suspectPath;
@property (nonatomic, copy) NSString *summary;
@property (nonatomic, copy) NSArray<NSString *> *tweakFrames;
@property (nonatomic, copy) NSArray<NSString *> *loadedTweakBases;
@property (nonatomic, copy, nullable) NSString *bundleID;
@property (nonatomic) BOOL watchdog;
- (NSDictionary *)dictionaryRepresentation;
@end

AFCrashInfo * _Nullable AFParseCrashReport(NSString *path);
NSArray<NSDictionary *> *AFCrashReportCandidates(NSTimeInterval maxAge);
NSArray<AFCrashInfo *> *AFRecentCrashReports(NSTimeInterval maxAge, NSUInteger limit);
AFCrashInfo * _Nullable AFNewestSpringBoardCrash(NSTimeInterval maxAge);
AFCrashInfo * _Nullable AFReadCrashMarker(void);
AFCrashInfo * _Nullable AFReadHangMarker(void);

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif
