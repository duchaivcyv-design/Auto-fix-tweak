DEBUG = 0
ARCHS = arm64 arm64e
TARGET = iphone:clang:15.6:14.0

PACKAGE_SCHEME ?= rootless
ifeq ($(PACKAGE_SCHEME),rootless)
THEOS_PACKAGE_SCHEME = rootless
else ifeq ($(PACKAGE_SCHEME),rootful)
# rootful: no scheme
else
$(error PACKAGE_SCHEME must be rootless or rootful)
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AutoFixTweak
AutoFixTweak_FILES = Tweak.xm \
	shared/AFCore.m \
	shared/AFTweakScanner.m \
	shared/AFCrashParser.m \
	tweak/AFCrashGuard.m \
	tweak/AFHangWatchdog.m \
	tweak/AFBridge.m \
	tweak/AFUI.m \
	tweak/AFCameraGuard.m \
	tweak/AFCameraRepair.m \
	tweak/AFCameraRepairHooks.xm
AutoFixTweak_FRAMEWORKS = Foundation UIKit AVFoundation
AutoFixTweak_CFLAGS = -fobjc-arc -I$(THEOS_PROJECT_DIR) -D_DARWIN_C_SOURCE -Wall -Wno-deprecated-declarations -g0

TOOL_NAME = AutoFixDaemon
AutoFixDaemon_FILES = daemon/main.m \
	daemon/AFProcess.m \
	daemon/AFQuarantine.m \
	daemon/AFAppGuard.m \
	shared/AFCore.m \
	shared/AFTweakScanner.m \
	shared/AFCrashParser.m
AutoFixDaemon_FRAMEWORKS = Foundation
AutoFixDaemon_CFLAGS = -fobjc-arc -I$(THEOS_PROJECT_DIR) -D_DARWIN_C_SOURCE -Wall -Wno-deprecated-declarations -g0
AutoFixDaemon_INSTALL_PATH = /usr/libexec

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/tool.mk
