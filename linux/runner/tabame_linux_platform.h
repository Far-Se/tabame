#ifndef TABAME_LINUX_PLATFORM_H_
#define TABAME_LINUX_PLATFORM_H_

#include <flutter_linux/flutter_linux.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct _TabameLinuxPlatform TabameLinuxPlatform;

TabameLinuxPlatform* tabame_linux_platform_new(FlView* view);
void tabame_linux_platform_free(TabameLinuxPlatform* platform);

#ifdef __cplusplus
}
#endif

#endif  // TABAME_LINUX_PLATFORM_H_
