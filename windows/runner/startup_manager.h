#ifndef RUNNER_STARTUP_MANAGER_H_
#define RUNNER_STARTUP_MANAGER_H_

#include <string>

namespace startup_manager {

struct Result {
  bool success;
  std::string value;
  std::string error;
};

Result IsPackaged();
Result GetStatus();
Result Enable();
Result Disable();

}  // namespace startup_manager

#endif  // RUNNER_STARTUP_MANAGER_H_
