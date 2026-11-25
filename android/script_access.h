#pragma once

#include "daScript/daScript.h"
#include "bundle_scripts.h"
#include <cstdlib>

inline auto android_script_access() {
    // The mobile runtime omits its desktop file system. Restrict the SDL
    // loader to the runtime directory installed by this Activity.
    auto access = das::make_smart<dassdl3_mobile::BundleAccess>();
    das::string prefix = std::getenv("DASRMLUI_HOME");
    access->addFileSystem(new dassdl3_mobile::BundleScripts(prefix + "/"), true, false);
    return access;
}
