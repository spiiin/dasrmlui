// Included after Gfx helpers and before RenderInterface_GL3 construction.
struct CustomProgram {
    GLuint program=0;
    bool filter=false;
    std::unordered_map<Rml::String,GLint> locations;
    ~CustomProgram() { if(program) glDeleteProgram(program); }
    GLint Location(const Rml::String& name) {
        auto found=locations.find(name);
        if(found!=locations.end()) return found->second;
        return locations.emplace(name,glGetUniformLocation(program,name.c_str())).first->second;
    }
    void Bind(const Rml::Dictionary& values,Rml::Vector2f size) {
        glUseProgram(program);
        glUniform1f(Location("u_time"),float(Rml::GetSystemInterface()->GetElapsedTime()));
        glUniform2f(Location("u_size"),size.x,size.y);
        glUniform2f(Location("u_texel"),size.x>0 ? 1.f/size.x : 0.f,size.y>0 ? 1.f/size.y : 0.f);
        for(const auto& entry:values) {
            if(entry.first.rfind("p_",0)!=0) continue;
            const auto location=Location(entry.first);
            if(entry.second.GetType()==Rml::Variant::VECTOR4) {
                auto value=entry.second.Get<Rml::Vector4f>(); glUniform4f(location,value.x,value.y,value.z,value.w);
            } else glUniform1f(location,entry.second.Get<float>());
        }
    }
};
struct RenderInterface_GL3::CustomEffects {
    std::unordered_map<Rml::String,std::shared_ptr<CustomProgram>> programs;
    int instances=0;
};
// Separate shared instance data so the original handles stay ABI-compatible.
struct CustomEffectInstance {
    std::shared_ptr<CustomProgram> program;
    Rml::Dictionary values;
    int* count;
    CustomEffectInstance(std::shared_ptr<CustomProgram> program,const Rml::Dictionary& values,int* count):program(std::move(program)),values(values),count(count) { ++*count; }
    ~CustomEffectInstance() { --*count; }
};
static GLuint CompileCustomStage(GLenum stage,const char* source,Rml::String& error) {
    GLuint shader=glCreateShader(stage);
    glShaderSource(shader,1,&source,nullptr); glCompileShader(shader);
    GLint ok=0; glGetShaderiv(shader,GL_COMPILE_STATUS,&ok);
    if(!ok) {
        GLint length=0; glGetShaderiv(shader,GL_INFO_LOG_LENGTH,&length);
        std::vector<char> log(size_t((std::max)(length,1))+1);
        glGetShaderInfoLog(shader,GLsizei(log.size()),nullptr,log.data()); error=log.data();
        glDeleteShader(shader); return 0;
    }
    return shader;
}
bool RenderInterface_GL3::RegisterEffect(const Rml::String& key,bool filter,const Rml::String& fragment,Rml::String& error) {
    if(!custom_effects) custom_effects=Rml::MakeUnique<CustomEffects>();
    if(custom_effects->programs.count(key)) { error="Duplicate GPU program"; return false; }
    const auto vertex=CompileCustomStage(GL_VERTEX_SHADER,filter ? shader_vert_passthrough : shader_vert_main,error);
    if(!vertex) return false;
    const auto pixel=CompileCustomStage(GL_FRAGMENT_SHADER,fragment.c_str(),error);
    if(!pixel) { glDeleteShader(vertex); return false; }
    GLuint program=glCreateProgram();
    for(GLuint i=0;i<GLuint(Gfx::VertexAttribute::Count);++i) glBindAttribLocation(program,i,Gfx::vertex_attribute_names[i]);
    glAttachShader(program,vertex); glAttachShader(program,pixel); glLinkProgram(program);
    glDetachShader(program,vertex); glDetachShader(program,pixel); glDeleteShader(vertex); glDeleteShader(pixel);
    GLint ok=0; glGetProgramiv(program,GL_LINK_STATUS,&ok);
    if(!ok) {
        GLint length=0; glGetProgramiv(program,GL_INFO_LOG_LENGTH,&length);
        std::vector<char> log(size_t((std::max)(length,1))+1);
        glGetProgramInfoLog(program,GLsizei(log.size()),nullptr,log.data()); error=log.data();
        glDeleteProgram(program); return false;
    }
    auto value=std::make_shared<CustomProgram>(); value->program=program; value->filter=filter;
    custom_effects->programs.emplace(key,std::move(value)); return true;
}
void RenderInterface_GL3::UnregisterEffect(const Rml::String& key) { if(custom_effects) custom_effects->programs.erase(key); }
bool RenderInterface_GL3::EffectInUse(const Rml::String& key) const {
    if(!custom_effects) return false;
    auto it=custom_effects->programs.find(key); return it!=custom_effects->programs.end() && it->second.use_count()>1;
}
Rml::Vector2i RenderInterface_GL3::EffectCounts() const {
    return custom_effects ? Rml::Vector2i{int(custom_effects->programs.size()),custom_effects->instances} : Rml::Vector2i{};
}
