"""Stage the existing daScript examples and browser-only host adapters."""
from pathlib import Path
import argparse
import shutil

ROOT=Path(__file__).resolve().parents[1]
def prepare(build: Path, sdl: Path, rml: Path):
    vfs=build/'preload'
    vfs.mkdir(parents=True,exist_ok=True)
    ignore=shutil.ignore_patterns('_aot_generated','_llvm_aot_generated','.jitted_scripts','__pycache__')
    for source,target in [(sdl/'third_party/daScript/daslib',vfs/'daScript/daslib'),
                          (sdl/'third_party/daScript/modules/dasGlsl/glsl',vfs/'daScript/modules/dasGlsl/glsl'),
                          (sdl/'third_party/daScript/modules/dasLiveHost/live',vfs/'daScript/modules/dasLiveHost/live'),
                          (ROOT/'dasrmlui',vfs/'dasrmlui'),(ROOT/'examples',vfs/'examples')]:
        shutil.copytree(source,target,dirs_exist_ok=True,ignore=ignore)
    for adapter in (ROOT/'web/examples').glob('*.das'): shutil.copy2(adapter,vfs/'examples'/adapter.name)
    fonts=vfs/'assets'; fonts.mkdir(exist_ok=True)
    for name in ['LatoLatin-Regular.ttf','LatoLatin-Bold.ttf','LatoLatin-Italic.ttf','LatoLatin-BoldItalic.ttf']:
        shutil.copy2(rml/'Samples/assets'/name,fonts/name)
    shutil.copy2(ROOT/'web/assets/DejaVuSans.ttf',fonts/'DejaVuSans.ttf')
    (vfs/'logs').mkdir(exist_ok=True)
    site=build/'site';site.mkdir(exist_ok=True)
    for name in ['index.html','example.html','gallery.js','player.js','style.css','examples.json']:
        source=ROOT/'web'/name
        if source.exists(): shutil.copy2(source,site/name)
    shutil.copytree(ROOT/'web/assets',site/'assets',dirs_exist_ok=True)
    licenses=site/'licenses';licenses.mkdir(exist_ok=True)
    for source,name in [(ROOT/'LICENSE','dasrmlui.txt'),(sdl/'LICENSE','dasSDL3.txt'),
                        (sdl/'third_party/daScript/LICENSE','daScript.txt'),
                        (rml/'LICENSE.txt','RmlUi.txt'),(rml/'Samples/assets/LICENSE.txt','Lato.txt'),
                        (ROOT/'web/assets/LICENSE-DejaVuSans.ttf.txt','DejaVuSans.txt')]:
        if source.exists():shutil.copy2(source,licenses/name)
    # Carry licenses for the actual renderer/font/vector dependencies too.
    for name in ['SDL','FreeType','daScript']:
        source=sdl/'licenses'/name
        if source.exists():shutil.copytree(source,licenses/name,dirs_exist_ok=True)
    cache={}
    cache_file=build/'CMakeCache.txt'
    if cache_file.exists():
        for line in cache_file.read_text(encoding='utf-8').splitlines():
            if '=' in line and ':' in line.split('=',1)[0]:
                key,value=line.split('=',1);cache[key.split(':',1)[0]]=value
    for key,folder in [('LUNASVG','lunasvg'),('RLOTTIE','rlottie')]:
        source=Path(cache.get('FETCHCONTENT_SOURCE_DIR_'+key) or build/'_deps'/(folder+'-src'))
        for name in ['LICENSE','COPYING']:
            if (source/name).exists():shutil.copy2(source/name,licenses/(folder+'-'+name+'.txt'))
        if (source/'licenses').exists():shutil.copytree(source/'licenses',licenses/folder,dirs_exist_ok=True)
        if (source/'plutovg/LICENSE').exists():shutil.copy2(source/'plutovg/LICENSE',licenses/'plutovg.txt')
    links=''.join(f'<li><a href="{f.name}">{f.stem}</a></li>' for f in sorted(licenses.glob('*.txt')))
    links+=''.join(f'<li><a href="{f.relative_to(licenses).as_posix()}">{f.relative_to(licenses).as_posix()}</a></li>' for f in sorted(licenses.rglob('*')) if f.is_file() and f.parent!=licenses)
    (licenses/'index.html').write_text('<!doctype html><meta charset="utf-8"><title>Licenses</title><a href="../">Gallery</a><h1>Licenses</h1><ul>'+links+'</ul>',encoding='utf-8')
    print(f'Staged browser sources and gallery: {site}')
if __name__=='__main__':
    p=argparse.ArgumentParser()
    p.add_argument('--build',type=Path,default=ROOT/'build/web')
    p.add_argument('--sdl',type=Path,default=ROOT.parent/'dasSDL3')
    p.add_argument('--rml',type=Path,default=ROOT.parent/'RmlUi')
    args=p.parse_args();prepare(args.build,args.sdl,args.rml)
