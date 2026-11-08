#import <Foundation/Foundation.h>
#import <sys/types.h>

NS_ASSUME_NONNULL_BEGIN

pid_t AFSpringBoardPID(void);
pid_t AFPIDForProcessNamed(NSString *name);
NSUInteger AFKillProcessNamed(NSString *name);

NS_ASSUME_NONNULL_END
