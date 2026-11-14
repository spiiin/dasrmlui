#pragma once

#include "bundle_scripts.h"

inline das::smart_ptr<das::FsFileAccess> ios_script_access(const char* root) {
    auto access = das::make_smart<dassdl3_ios::BundleAccess>();
    access->addFileSystem(new dassdl3_ios::BundleScripts(root), true, false);
    return access;
}
