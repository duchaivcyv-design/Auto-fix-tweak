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
AutoFixTweak_FILES = Tweak.xm
AutoFixTweak_FRAMEWORKS = Foundation UIKit AVFoundation
AutoFixTweak_CFLAGS = -fobjc-arc -D_DARWIN_C_SOURCE -Wall -Wno-deprecated-declarations -g0

include $(THEOS_MAKE_PATH)/tweak.mk
