#import <Foundation/Foundation.h>
#import "shared/AFCore.h"

#ifdef __cplusplus
extern "C" {
#endif

NS_ASSUME_NONNULL_BEGIN

@interface AFTweakInfo : NSObject
@property (nonatomic, copy) NSString *base;
@property (nonatomic, copy, nullable) NSString *plistPath;
@property (nonatomic, copy, nullable) NSString *dylibPath;
@property (nonatomic, copy, nullable) NSString *disabledPlistPath;
@property (nonatomic, copy, nullable) NSString *disabledDylibPath;
@property (nonatomic, copy, nullable) NSString *package;
@property (nonatomic) NSTimeInterval installTime;
@property (nonatomic) NSTimeInterval mtime;
@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) BOOL hasFilter;
- (NSDictionary *)dictionaryRepresentation;
@end

NSDictionary<NSString *, AFTweakInfo *> *AFScanTweakMap(void);
NSArray<AFTweakInfo *> *AFScanTweaks(void);
AFTweakInfo * _Nullable AFTweakInfoForBase(NSString *base);

/* Đọc Filter trong plist để biết tweak có được nạp vào bundle/executable hay không. */
BOOL AFTweakInfoMayLoadInProcess(AFTweakInfo *info,
                                 NSString * _Nullable bundleID,
                                 NSString * _Nullable executable);
BOOL AFTweakInfoExplicitlyTargetsBundle(AFTweakInfo *info,
                                        NSString * _Nullable bundleID,
                                        NSString * _Nullable executable);
NSDictionary<NSString *, NSNumber *> *AFPackageInstallTimes(void);
NSDictionary<NSString *, NSString *> *AFPathToPackageMap(void);
NSDictionary<NSString *, id> *AFBuildManifest(NSArray<AFTweakInfo *> *tweaks);
NSDictionary * _Nullable AFLastGoodManifest(void);
BOOL AFSaveLastGoodManifest(NSDictionary *manifest);
NSArray<AFTweakInfo *> *AFRecentlyInstalledTweaks(NSArray<AFTweakInfo *> *all,
                                                  NSTimeInterval since,
                                                  NSSet<NSString *> *exclude);

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif
