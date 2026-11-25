#pragma once

#include "daScript/daScript.h"
#ifdef __ANDROID__
#include "bundle_scripts.h"
#include <cstdlib>
#endif

inline auto rui_script_access() {
#ifdef __ANDROID__
    // The mobile runtime omits its desktop file system. Restrict the SDL
    // loader to the runtime directory installed by this Activity.
    auto access = das::make_smart<dassdl3_mobile::BundleAccess>();
    das::string prefix = std::getenv("DASRMLUI_HOME");
    access->addFileSystem(new dassdl3_mobile::BundleScripts(prefix + "/"), true, false);
    return access;
#else
    return das::make_smart<das::FsFileAccess>();
#endif
}
