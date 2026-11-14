#pragma once

#include "bundle_scripts.h"

inline das::smart_ptr<das::FsFileAccess> ios_script_access(const char* root, const char* editable_root = nullptr) {
    auto access = das::make_smart<dassdl3_ios::BundleAccess>();
    access->addFileSystem(new dassdl3_ios::BundleScripts(root), true, false);
    if (editable_root && *editable_root)
        access->addFileSystem(new dassdl3_ios::BundleScripts(editable_root), true, false);
    return access;
}
