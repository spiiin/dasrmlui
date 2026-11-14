#pragma once
#include <string>
int run_ui_live(const char* path,const char* styles,const std::string& das_root,
    const std::string& sdl_root,const std::string& ui_root,const std::string& examples_root,bool hidden,int frames,
    const std::string& editable_root = {});
