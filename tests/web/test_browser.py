"""Browser gallery and real WebGL smoke tests. Requires playwright and Pillow."""
import argparse, json
from pathlib import Path
from io import BytesIO
from PIL import Image, ImageChops
from playwright.sync_api import sync_playwright

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--url',default='http://127.0.0.1:8766')
p.add_argument('--only',default='')
p.add_argument('--browser',choices=['msedge','chromium'],default='msedge')
p.add_argument('--software-gl',action='store_true')
p.add_argument('--output',type=Path,default=Path('logs/web'))
a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
manifest=json.loads((Path(__file__).resolve().parents[2]/'web/examples.json').read_text(encoding='utf-8'))
with sync_playwright() as pw:
    browser=pw.chromium.launch(channel='msedge' if a.browser=='msedge' else None,headless=True,
        args=['--use-angle=swiftshader','--enable-unsafe-swiftshader'] if a.software_gl else [])
    page=browser.new_page(viewport={'width':1440,'height':1100})
    page.goto(a.url)
    page.wait_for_function('document.querySelectorAll(".card").length===24')
    page.locator('.preview img').evaluate_all('(images)=>Promise.all(images.map(i=>{i.loading="eager";return i.decode()}))')
    assert page.locator('.card:visible').count()==24
    assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
    page.screenshot(path=str(a.output/'gallery-desktop.png'),full_page=True)
    page.screenshot(path=str(a.output/'gallery-preview.png'))
    page.locator('#search').fill('shader')
    assert page.locator('.card:visible').count()==1
    page.locator('#search').fill('no_such_demo')
    assert page.locator('#empty').is_visible()
    page.locator('#search').fill('')
    page.get_by_role('button',name='Графика',exact=True).click()
    assert page.locator('.card:visible').count()==5
    page.get_by_role('button',name='Все',exact=True).click()
    page.set_viewport_size({'width':390,'height':844})
    assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
    page.screenshot(path=str(a.output/'gallery-mobile.png'),full_page=True)
    page.screenshot(path=str(a.output/'gallery-mobile-preview.png'))
    page.close()
    print('Gallery: cards, images, search, categories, desktop/mobile PASS',flush=True)
    for demo in manifest:
        if a.only and demo['id'] not in a.only.split(','):continue
        page=browser.new_page(viewport={'width':1280,'height':1024})
        errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
        page.on('console',lambda msg:print('browser:',msg.type,msg.text,flush=True))
        page.goto(a.url+'/example.html?demo='+demo['id'])
        page.wait_for_function("['ready','error'].includes(document.body.dataset.state)",timeout=180000)
        output=page.locator('#log').text_content()
        assert page.locator('body').get_attribute('data-state')=='ready',demo['id']+'\n'+page.locator('#error').inner_text()+'\n'+output
        page.wait_for_timeout(500)
        page.screenshot(path=str(a.output/(demo['id']+'-page.png')))
        shot=page.locator('canvas').screenshot()
        im=Image.open(BytesIO(shot)).convert('RGB')
        assert len(im.getcolors(im.width*im.height) or [])>100,'Blank frame: '+demo['id']
        (a.output/(demo['id']+'.png')).write_bytes(shot)
        if demo['id']=='dashboard':
            canvas=page.locator('canvas')
            before=im.crop((410,185,500,240))
            canvas.click(position={'x':333,'y':525})
            page.wait_for_timeout(150)
            changed=Image.open(BytesIO(canvas.screenshot())).convert('RGB')
            assert ImageChops.difference(before,changed.crop((410,185,500,240))).getbbox(),'Complete click did not update metric'
            before=changed.crop((48,470,665,760))
            canvas.click(position={'x':150,'y':365})
            page.keyboard.type('November')
            page.wait_for_timeout(150)
            changed=Image.open(BytesIO(canvas.screenshot())).convert('RGB')
            assert ImageChops.difference(before,changed.crop((48,470,665,760))).getbbox(),'Text input did not filter tasks'
            page.set_viewport_size({'width':720,'height':950})
            page.wait_for_function('document.querySelector("canvas").width===720')
            assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
        if demo['id']=='live_lab':
            canvas=page.locator('canvas')
            canvas.click(position={'x':220,'y':280})
            page.keyboard.press('Control+A');page.keyboard.type('Browser reload test')
            page.wait_for_timeout(150)
            canvas.click(position={'x':230,'y':80})
            before=Image.open(BytesIO(canvas.screenshot())).convert('RGB').crop((40,260,650,310))
            assert ImageChops.difference(im.crop((40,260,650,310)),before).getbbox(),'LiveHost input did not change'
            canvas.click(position={'x':85,'y':180})
            page.wait_for_function('document.querySelector("#log").textContent.includes("[live] reloaded")',timeout=60000)
            after=Image.open(BytesIO(canvas.screenshot())).convert('RGB').crop((40,260,650,310))
            assert not ImageChops.difference(before,after).getbbox(),'LiveHost lost edited state'
        assert not errors,errors
        assert 'Script exception:'  not in output and 'Failed to compile' not in output,output
        page.evaluate('uiRuntime._rui_web_stop()')
        page.wait_for_function("['stopped','error'].includes(document.body.dataset.state)",timeout=10000)
        assert page.locator('body').get_attribute('data-state')=='stopped',page.locator('#log').text_content()
        assert not errors,errors
        page.close()
        print(demo['id']+' WebGL frame / stop PASS',flush=True)
    page=browser.new_page()
    page.goto(a.url+'/example.html?demo=../../invalid')
    page.wait_for_function("document.body.dataset.state==='error'")
    assert 'не найден' in page.locator('#error').inner_text()
    page.close();browser.close()
