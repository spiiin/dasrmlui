"""Fetch exact public source revisions for the Web build; never alter SDK checkouts."""
import argparse
import json
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]

def fetch(destination):
    manifest=json.loads((ROOT/'web/dependencies.json').read_text(encoding='utf-8'))
    destination=destination.resolve()
    for name,entry in manifest.items():
        target=destination/name
        target.mkdir(parents=True,exist_ok=True)
        def git(*args,capture=False):
            return subprocess.run(['git','-C',str(target),*args],check=True,text=True,
                                  stdout=subprocess.PIPE if capture else None).stdout
        if not (target/'.git').exists():
            # Submodule entries in the parent checkout start as empty directories.
            if any(target.iterdir()):raise RuntimeError(f'Refusing nonempty non-Git directory: {target}')
            git('init');git('remote','add','origin',entry['url'])
        if git('remote','get-url','origin',capture=True).strip()!=entry['url']:
            raise RuntimeError(f'Unexpected remote: {target}')
        if git('status','--porcelain','--untracked-files=no',capture=True).strip():
            raise RuntimeError(f'Refusing modified dependency: {target}')
        git('fetch','--depth','1','origin',entry['revision'])
        git('checkout','--detach',entry['revision'])
        actual=git('rev-parse','HEAD',capture=True).strip()
        if actual!=entry['revision']:raise RuntimeError(f'Revision mismatch: {target}')
        print(f'{name}: {actual}',flush=True)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--destination',type=Path,default=ROOT/'build/web-deps')
    fetch(p.parse_args().destination)
