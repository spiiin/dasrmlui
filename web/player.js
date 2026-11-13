const $=id=>document.getElementById(id);
const canvas=$('canvas');
let runtime, ready=false, failed=false;
const lines=[];
function log(text){ lines.push(String(text)); if(lines.length>300)lines.shift(); $('log').textContent=lines.join('\n'); }
function fail(error){ failed=true; $('loader').hidden=true; $('error').hidden=false; $('error').textContent=String(error); $('status').textContent='Не удалось запустить пример'; document.body.dataset.state='error'; }
function onReady(){ if(failed||ready)return; ready=true; $('loader').hidden=true; canvas.style.visibility="visible"; $('status').textContent='Пример запущен · мышь, клавиатура и прокрутка'; document.body.dataset.state='ready'; canvas.focus(); }
$('restart').onclick=()=>location.reload();
$('fullscreen').onclick=()=>canvas.requestFullscreen().catch(fail);
canvas.addEventListener('contextmenu',event=>event.preventDefault());
canvas.addEventListener('keydown',event=>{if(['Tab','ArrowUp','ArrowDown','ArrowLeft','ArrowRight',' ','F5'].includes(event.key))event.preventDefault();});
canvas.addEventListener('webglcontextlost',event=>{event.preventDefault();fail('Контекст WebGL потерян. Перезапустите пример.');});
window.addEventListener('pagehide',()=>runtime?._rui_web_stop());
try {
  const response=await fetch('examples.json'); if(!response.ok)throw Error('Не удалось загрузить список примеров');
  const examples=await response.json();
  const id=new URLSearchParams(location.search).get('demo');
  const example=examples.find(item=>item.id===id);
  if(!example)throw Error('Пример не найден. Вернитесь в галерею и выберите карточку.');
  $('title').textContent=example.title; document.title=example.title+' · dasrmlui';
  $('live-note').hidden=id!=='live_lab';
  if(!WebAssembly.Suspending)throw Error('Для запуска требуется поддержка WebAssembly JSPI. Откройте страницу в актуальном Chrome или Edge.');
  if(!document.createElement('canvas').getContext('webgl2'))throw Error('Для запуска требуется браузер с WebGL 2.');
  await new Promise((resolve,reject)=>{const script=document.createElement('script');script.src='dasrmlui_web.js';script.onload=resolve;script.onerror=()=>reject(Error('Движок не найден. Соберите веб-версию через tools/build_web.ps1.'));document.head.append(script);});
  runtime=await window.createDasRmlUi({canvas,noInitialRun:true,onUiReady:onReady,
    print:text=>{log(text); if(String(text).includes('[live] ready'))setTimeout(onReady,100);},printErr:log,
    onAbort:reason=>fail('Ошибка движка: '+reason),
    setStatus:text=>{if(text&&!ready)$('status').textContent=text;},
    monitorRunDependencies:left=>{if(!ready)$('status').textContent=left?'Загрузка ресурсов…':'Компиляция daScript…';}});
  window.uiRuntime=runtime;
  const args=['/examples/'+id+'.das'];
  if(id==='live_lab')args.push('--watch','--styles','/examples/live_lab_styles.das');
  const result=await runtime.callMain(args);
  if(result)fail('Пример завершился с кодом '+result+'. Подробности в журнале.');
  else if(ready){document.body.dataset.state='stopped';$('status').textContent='Пример остановлен';}
  else fail('Пример завершился до первого кадра. Подробности в журнале.');
} catch(error){fail(error.message||error);}
