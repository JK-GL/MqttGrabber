include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MqttGrabber

MqttGrabber_FILES = Tweak.x
MqttGrabber_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
MqttGrabber_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
