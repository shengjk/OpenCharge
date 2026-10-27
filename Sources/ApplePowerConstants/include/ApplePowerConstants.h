#ifndef OPENCHARGE_APPLE_POWER_CONSTANTS_H
#define OPENCHARGE_APPLE_POWER_CONSTANTS_H
#include <stdint.h>
uint32_t opencharge_can_system_sleep(void);
uint32_t opencharge_system_will_sleep(void);
uint32_t opencharge_system_has_powered_on(void);
uint32_t opencharge_clamshell_state_changed(void);

#include <CoreFoundation/CoreFoundation.h>
#include <Security/Authorization.h>
#include <ServiceManagement/ServiceManagement.h>
// These public APIs are required only by the macOS 11/12 registration route.
// Keep their intentional deprecation scope here; do not weaken Swift API gates.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static inline int opencharge_legacy_helper_status(void) {
 CFDictionaryRef job = SMJobCopyDictionary(kSMDomainSystemLaunchd, CFSTR("org.opencharge.charged"));
 if (!job) return 0;
 CFTypeRef label = CFDictionaryGetValue(job, CFSTR("Label"));
 CFTypeRef arguments = CFDictionaryGetValue(job, CFSTR("ProgramArguments"));
 int matches = label && CFGetTypeID(label) == CFStringGetTypeID() && CFEqual(label, CFSTR("org.opencharge.charged")) &&
  arguments && CFGetTypeID(arguments) == CFArrayGetTypeID() && CFArrayGetCount(arguments) == 1 &&
  CFEqual(CFArrayGetValueAtIndex(arguments, 0), CFSTR("/Library/PrivilegedHelperTools/org.opencharge.charged"));
 CFRelease(job);
 return matches ? 1 : 2;
}
static inline int opencharge_bless_legacy_helper(AuthorizationRef authorization, CFErrorRef *error) {
 return SMJobBless(kSMDomainSystemLaunchd, CFSTR("org.opencharge.charged"), authorization, error);
}
static inline int opencharge_remove_legacy_helper_job(AuthorizationRef authorization, CFErrorRef *error) {
 return SMJobRemove(kSMDomainSystemLaunchd, CFSTR("org.opencharge.charged"), authorization, true, error);
}
#pragma clang diagnostic pop

#endif
