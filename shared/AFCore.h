#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const AFVersion;
FOUNDATION_EXPORT NSString * const AFAuthor;
FOUNDATION_EXPORT NSString * const AFDaemonLabel;

/* Paths */
NSString *AFJBRoot(void);
BOOL AFIsRootless(void);
NSString *AFStateDir(void);
NSString *AFTweakStatePath(void);
NSString *AFDaemonStatePath(void);
NSString *AFConfigPath(void);
NSString *AFRequestsDir(void);
NSString *AFLastGoodPath(void);
NSString *AFTweakLogPath(void);
NSString *AFDaemonLogPath(void);
NSString *AFCrashMarkerPath(void);
NSString *AFHangMarkerPath(void);
NSString *AFCameraMarkerPath(void);
NSString *AFDPKGStatusPath(void);
NSString *AFDPKGInfoDir(void);

NSArray<NSString *> *AFDynamicLibraryDirs(void);
NSArray<NSString *> *AFCrashReportDirs(void);

/* Files / plists / logging */
BOOL AFFileExists(NSString *path);
BOOL AFEnsureDirectory(NSString *path, int mode);
void AFEnsureStateDir(void);
void AFEnsureRequestsDir(void);
void AFChownMobile(NSString *path);
NSDictionary * _Nullable AFReadPlist(NSString *path);
BOOL AFWritePlist(NSString *path, NSDictionary *dict);
BOOL AFWritePlistSecure(NSString *path, NSDictionary *dict);
NSTimeInterval AFNow(void);
NSString *AFTimeString(NSTimeInterval interval);
NSArray<NSString *> *AFSplitLines(NSString *text);
void AFLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
void AFLogTo(NSString *path, NSString *format, ...) NS_FORMAT_FUNCTION(2, 3);

/* Config */
NSDictionary *AFDefaultConfig(void);
NSDictionary *AFLoadConfig(void);

/* Tweak naming / classification */
NSString *AFSanitizeToken(NSString *token);
NSString *AFNormalizePath(NSString *path);
NSString *AFBaseFromTweakFileName(NSString *fileName);
BOOL AFIsWhitelistedTweakBase(NSString *base);
BOOL AFIsSelfTweakBase(NSString *base);
BOOL AFIsTweakImagePath(NSString *path);

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif
