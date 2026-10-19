#include "ApplePowerConstants.h"
#include <IOKit/IOMessage.h>
#include <IOKit/pwr_mgt/IOPM.h>
// Swift cannot import these function-like C macros; use the selected SDK definitions.
uint32_t opencharge_can_system_sleep(void) { return kIOMessageCanSystemSleep; }
uint32_t opencharge_system_will_sleep(void) { return kIOMessageSystemWillSleep; }
uint32_t opencharge_system_has_powered_on(void) { return kIOMessageSystemHasPoweredOn; }
uint32_t opencharge_clamshell_state_changed(void) { return kIOPMMessageClamshellStateChange; }
