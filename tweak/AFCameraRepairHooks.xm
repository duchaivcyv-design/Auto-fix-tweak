#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

#import "shared/AFCore.h"
#import "tweak/AFCameraRepair.h"

/* Các hook dưới đây chỉ hoạt động trong tiến trình Camera/FaceTime.
   Mục tiêu: giữ tweak gây lỗi tiếp tục chạy, chỉ sửa phần camera bị nó can thiệp. */

%hook AVCaptureDevice

+ (AVCaptureDevice *)defaultDeviceWithPosition:(AVCaptureDevicePosition)position {
    AVCaptureDevice *device = %orig;
    if (device || position != AVCaptureDevicePositionFront) return device;
    if (!AFCameraRepairEnabled() || AFInCameraRepair()) return device;
    AVCaptureDevice *fallback = AFFrontCameraFallbackDevice();
    if (fallback) {
        AFLog(@"CameraRepair: khôi phục defaultDeviceWithPosition:Front");
        return fallback;
    }
    return device;
}

+ (AVCaptureDevice *)defaultDeviceWithDeviceType:(AVCaptureDeviceType)deviceType
                                       mediaType:(AVMediaType)mediaType
                                        position:(AVCaptureDevicePosition)position {
    AVCaptureDevice *device = %orig;
    if (device || position != AVCaptureDevicePositionFront) return device;
    if (!AFCameraRepairEnabled() || AFInCameraRepair()) return device;
    AVCaptureDevice *fallback = AFFrontCameraFallbackDevice();
    if (fallback) {
        AFLog(@"CameraRepair: khôi phục defaultDeviceWithDeviceType position:Front");
        return fallback;
    }
    return device;
}

+ (NSArray *)devicesWithMediaType:(AVMediaType)mediaType {
    NSArray *devices = %orig;
    if (!AFCameraRepairEnabled() || AFInCameraRepair()) return devices;
    return AFRepairDeviceList(devices);
}

- (NSArray *)formats {
    NSArray *formats = %orig;
    if (formats.count > 0 || self.position != AVCaptureDevicePositionFront) return formats;
    if (!AFCameraRepairEnabled() || AFInCameraRepair()) return formats;

    AVCaptureDevice *fallback = AFFrontCameraFallbackDevice();
    if (fallback && fallback != self) {
        BOOL previous = AFInCameraRepair();
        AFSetCameraRepairGuard(YES);
        NSArray *altFormats = nil;
        @try {
            altFormats = [fallback formats];
        } @catch (NSException *exception) {
            altFormats = nil;
        }
        AFSetCameraRepairGuard(previous);
        if (altFormats.count) {
            AFLog(@"CameraRepair: khôi phục %lu format camera trước",
                  (unsigned long)altFormats.count);
            return altFormats;
        }
    }

    AVCaptureDeviceFormat *active = self.activeFormat;
    if (active) {
        AFLog(@"CameraRepair: dùng activeFormat cho camera trước");
        return @[active];
    }
    return formats;
}

%end

%hook AVCaptureDeviceDiscoverySession

- (NSArray *)devices {
    NSArray *devices = %orig;
    if (!AFCameraRepairEnabled() || AFInCameraRepair()) return devices;
    return AFRepairDeviceList(devices);
}

%end

%hook AVCaptureDeviceInput

- (instancetype)initWithDevice:(AVCaptureDevice *)device error:(NSError **)error {
    id result = %orig;
    if (result || !device || device.position != AVCaptureDevicePositionFront) return result;
    if (!AFCameraRepairEnabled() || AFInCameraRepair()) return result;

    AVCaptureDevice *fallback = AFFrontCameraFallbackDevice();
    if (!fallback || fallback == device) return result;

    BOOL previous = AFInCameraRepair();
    AFSetCameraRepairGuard(YES);
    id retry = [[AVCaptureDeviceInput alloc] initWithDevice:fallback error:error];
    AFSetCameraRepairGuard(previous);

    if (retry) {
        AFLog(@"CameraRepair: tạo lại input camera trước bằng thiết bị dự phòng");
        return retry;
    }
    return result;
}

%end

%hook AVCaptureSession

- (void)addInput:(AVCaptureInput *)input {
    @try {
        %orig;
    } @catch (NSException *exception) {
        AFLog(@"CameraRepair: addInput ném lỗi %@", exception.reason ?: exception.name);
        if (![input isKindOfClass:[AVCaptureDeviceInput class]]) return;

        AVCaptureDevice *device = ((AVCaptureDeviceInput *)input).device;
        if (device.position != AVCaptureDevicePositionFront || AFInCameraRepair()) return;

        AVCaptureDevice *fallback = AFFrontCameraFallbackDevice();
        if (!fallback || fallback == device) return;

        NSError *error = nil;
        AVCaptureDeviceInput *fresh = [AVCaptureDeviceInput deviceInputWithDevice:fallback
                                                                           error:&error];
        if (!fresh) return;
        @try {
            %orig(fresh);
            AFLog(@"CameraRepair: thêm lại input camera trước sau lỗi");
        } @catch (NSException *second) {
            AFLog(@"CameraRepair: vẫn không thêm được input camera trước: %@",
                  second.reason ?: second.name);
        }
    }
}

- (void)addOutput:(AVCaptureOutput *)output {
    @try {
        %orig;
    } @catch (NSException *exception) {
        AFLog(@"CameraRepair: addOutput ném lỗi %@", exception.reason ?: exception.name);
    }
}

- (void)startRunning {
    @try {
        %orig;
    } @catch (NSException *exception) {
        AFLog(@"CameraRepair: startRunning ném lỗi %@", exception.reason ?: exception.name);
    }
}

%end

%hook AVCaptureDevice

- (BOOL)lockForConfiguration:(NSError **)error {
    @try {
        return %orig;
    } @catch (NSException *exception) {
        AFLog(@"CameraRepair: lockForConfiguration ném lỗi %@",
              exception.reason ?: exception.name);
        if (error) {
            *error = [NSError errorWithDomain:@"AutoFixTweak.CameraRepair"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    exception.reason ?: @"camera repair"}];
        }
        return NO;
    }
}

%end

%hook AVCaptureVideoPreviewLayer

- (void)setSession:(AVCaptureSession *)session {
    @try {
        %orig;
    } @catch (NSException *exception) {
        AFLog(@"CameraRepair: preview setSession ném lỗi %@",
              exception.reason ?: exception.name);
    }
}

%end
