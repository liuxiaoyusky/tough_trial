import {keyFor, validateBundle, mergeAnnotations, onImage} from './annotations.mjs';
const $ = id => document.getElementById(id);
let manifest, current, annotations = [], mode = '', draft = null, drawing = null, imageReady = false, storageReady = false;
const kinds = {device:'真机截图',simulator:'原生模拟器截图',design:'概念稿 · 未验证实现一致性',web:'网页实际截图',desktop:'桌面实际截图','native-preview':'原生设计预览 · 业务待实现'};
function message(text, error=false) { $('status').textContent=text; $('status').classList.toggle('error',error); }
function element(tag,text,cls='') { const e=document.createElement(tag); e.textContent=text; e.className=cls; return e; }
function action(text,fn,cls='') { const e=element('button',text,cls); e.type='button'; e.onclick=fn; return e; }
function bundle(values=annotations) { return {schema:1,project:manifest.project,annotations:values}; }
function save(values) {
  if (!storageReady) { message('本地批注未能读取，为避免覆盖，暂不可保存。',true); return false; }
  try { validateBundle(bundle(values),manifest.project); localStorage.setItem(keyFor(manifest.project),JSON.stringify(bundle(values))); annotations=values; render(); message('已保存在当前浏览器；导出后可发回给我。'); return true; }
  catch { message('保存失败，请保留此页面并导出已有批注；当前输入未丢失。',true); return false; }
}
function filtered() { return manifest.pages.filter(p => (!$('feature').value || p.feature_id===$('feature').value) && ($('kindFilter').value==='all' || ($('kindFilter').value==='design' ? p.kind==='design' : p.kind!=='design'))); }
function setMode(next='') {
  mode=next; $('canvas').classList.toggle('drawing',mode==='draw'); $('canvas').classList.toggle('pointing',mode==='point');
  $('draw').setAttribute('aria-pressed',String(mode==='draw')); $('point').setAttribute('aria-pressed',String(mode==='point'));
  $('hint').textContent=mode==='draw'?'用手指圈出要改的地方，松手填写意见；再次点“画圈”退出。':mode==='point'?'轻点画面，写下这处的意见。':'图中控件为静态画面；点“画圈”标出要改的位置。';
}
function choose(page) {
  if (!page) return;
  current=page; draft=null; drawing=null; imageReady=false; setMode();
  $('draw').disabled=$('point').disabled=true;
  history.replaceState(null,'','#'+page.id); $('title').textContent=page.title;
  $('kind').textContent=kinds[page.kind]; $('kind').classList.toggle('concept',page.kind==='design');
  $('provenance').textContent=page.provenance;
  $('image').src=page.image; $('image').alt=page.title+' — '+page.provenance;
  $('viewport').scrollTop=$('viewport').scrollLeft=0; window.scrollTo(0,0); render();
}
function render() {
  if (!current) return;
  $('marks').replaceChildren(); $('pins').replaceChildren();
  const visible=onImage(annotations,current);
  visible.forEach((n,i) => {
    n.strokes.forEach(stroke=>drawPath(stroke,n.resolved));
    const b=action('',()=>edit(n),'pin'+(n.resolved?' resolved':'')); b.append(element('span',String(i+1)));
    b.style.left=n.x*100+'%'; b.style.top=n.y*100+'%'; b.setAttribute('aria-label','批注 '+(i+1)+'：'+n.text); $('pins').append(b);
  });
  if (draft) draft.strokes.forEach(stroke=>drawPath(stroke));
  $('notes').textContent='批注 '+visible.length;
  const list=filtered(), index=list.findIndex(p=>p.id===current.id);
  $('position').textContent=index<0?'—':`${index+1}/${list.length}`;
  $('previous').disabled=index<=0; $('next').disabled=index<0||index===list.length-1;
  renderList(); renderNotes();
}
function drawPath(stroke,resolved=false) {
  const p=document.createElementNS('http://www.w3.org/2000/svg','path');
  p.setAttribute('d',stroke.map((v,i)=>(i?'L':'M')+(v.x*1000).toFixed(2)+' '+(v.y*1000).toFixed(2)).join(' '));
  if(resolved)p.style.stroke='#64748b'; $('marks').append(p); return p;
}
function renderList() {
  $('pageList').replaceChildren(); const list=filtered();
  if(!list.length)$('pageList').append(element('p','此筛选下没有画面。','caption'));
  list.forEach(p=>{const b=action(p.title,()=>{choose(p);$('catalogDialog').close();}); b.append(element('small',kinds[p.kind]+' · '+p.provenance)); b.setAttribute('aria-current',String(p.id===current.id)); $('pageList').append(b);});
}
function renderNotes() {
  $('noteList').replaceChildren();
  const currentNotes=onImage(annotations,current), old=annotations.filter(n=>!manifest.pages.some(p=>p.id===n.page&&p.revision===n.revision));
  if(!currentNotes.length)$('noteList').append(element('p','这张画面还没有批注。','caption'));
  for(const n of currentNotes) {
    const card=element('article','','note'); card.append(element('small',n.resolved?'已处理':'待处理'),element('p',n.text));
    const actions=element('div','','actions');
    actions.append(action('编辑',()=>{$('notesDialog').close();edit(n);}),action(n.resolved?'重新打开':'标为已处理',()=>save(annotations.map(v=>v.id===n.id?{...v,resolved:!v.resolved,updatedAt:new Date().toISOString()}:v))),action('删除',()=>{if(confirm('删除这条批注？'))save(annotations.filter(v=>v.id!==n.id));},'danger'));
    card.append(actions); $('noteList').append(card);
  }
  $('noteList').append(element('p',`本项目共 ${annotations.length} 条；导出包含全部页面。`,'caption'));
  if(old.length) {
    const details=element('details'); details.append(element('summary',`${old.length} 条属于历史画面，已保留`));
    old.forEach(n=>{const item=element('article','','note');item.append(element('small',n.title+' · '+n.provenance+' · '+n.revision.slice(0,12)),element('p',n.text)); details.append(item);}); $('noteList').append(details);
  }
  $('export').disabled=!annotations.length;
}
function edit(note) {
  draft=JSON.parse(JSON.stringify(note)); setMode(); $('comment').value=draft.text||''; $('undoStroke').disabled=!draft.strokes.length;
  render(); $('noteDialog').showModal(); $('comment').focus();
}
function newNote(position,strokes=[]) {
  return {id:crypto.randomUUID(),page:current.id,feature:current.feature_id,revision:current.revision,title:current.title,provenance:current.provenance,...position,strokes,text:'',resolved:false,updatedAt:new Date().toISOString()};
}
function coordinate(e) { const r=$('image').getBoundingClientRect(); return {x:Math.max(0,Math.min(1,(e.clientX-r.left)/r.width)),y:Math.max(0,Math.min(1,(e.clientY-r.top)/r.height))}; }
$('marks').onpointerdown=e=>{
  if(mode!=='draw'||!imageReady||!e.isPrimary||e.button!==0)return;
  e.preventDefault(); const points=[coordinate(e)]; drawing={id:e.pointerId,points,path:drawPath(points)}; $('marks').setPointerCapture(e.pointerId);
};
$('marks').onpointermove=e=>{if(!drawing||drawing.id!==e.pointerId)return; if(drawing.points.length<4000)drawing.points.push(coordinate(e));drawing.path.setAttribute('d',drawing.points.map((p,i)=>(i?'L':'M')+p.x*1000+' '+p.y*1000).join(' '));};
$('marks').onpointerup=e=>{if(!drawing||drawing.id!==e.pointerId)return;const points=drawing.points;drawing=null;$('marks').releasePointerCapture(e.pointerId);edit(newNote(points[0],points.length>1?[points]:[]));};
$('marks').onpointercancel=()=>{drawing=null;render();};
$('canvas').onclick=e=>{if(mode==='point'&&imageReady&&!e.target.closest('button'))edit(newNote(coordinate(e)));};
$('image').onload=()=>{imageReady=true;$('draw').disabled=$('point').disabled=!storageReady;};
$('image').onerror=()=>{imageReady=false;$('draw').disabled=$('point').disabled=true;message('图片加载失败，暂不能标注。请联网后刷新。',true);};
$('draw').onclick=()=>setMode(mode==='draw'?'':'draw'); $('point').onclick=()=>setMode(mode==='point'?'':'point');
$('zoom').onclick=()=>{const large=$('canvas').classList.toggle('zoomed');$('zoom').textContent=large?'适应':'放大';$('zoom').setAttribute('aria-pressed',String(large));};
$('catalog').onclick=()=>$('catalogDialog').showModal();
$('notes').onclick=()=>{renderNotes();$('notesDialog').showModal();};
$('feature').onchange=$('kindFilter').onchange=()=>{const list=filtered();if(list.length&&!list.some(p=>p.id===current.id))choose(list[0]);else render();};
for(const [id,delta] of [['previous',-1],['next',1]])$(id).onclick=()=>{const list=filtered();choose(list[list.findIndex(p=>p.id===current.id)+delta]);};
document.querySelectorAll('[data-close]').forEach(b=>b.onclick=()=>$(b.dataset.close).close());
$('noteDialog').onclose=()=>{draft=null;drawing=null;render();};
$('undoStroke').onclick=()=>{draft.strokes.pop();$('undoStroke').disabled=!draft.strokes.length;render();};
$('noteForm').onsubmit=e=>{
  e.preventDefault();const text=$('comment').value.trim();if(!draft||!text)return;
  const item={...draft,text,updatedAt:new Date().toISOString()};
  const values=annotations.some(n=>n.id===item.id)?annotations.map(n=>n.id===item.id?item:n):[...annotations,item];
  if(save(values))$('noteDialog').close();else alert('保存失败，意见仍在输入框中，请先复制保留。');
};
$('details').onclick=()=>{
  const box=$('sourceDetails');box.replaceChildren();
  [current.feature_id+' · '+current.route,kinds[current.kind],current.provenance,current.kind==='design'?'此图为概念探索；最终外观需用产品同一套 UI 组件渲染后再评审（iOS 使用 SwiftUI）。':'这是实际渲染的原始画面，未用网页重绘；历史截图不等于当前安装版本。','功能状态：'+current.implementation_status,'验收：'+current.verification,'图片版本：'+current.revision.slice(0,12)].forEach(t=>box.append(element('p',t)));
  const code=element('details');code.append(element('summary','代码与验收来源'));current.code.forEach(c=>code.append(element('p',c.symbol+' — '+c.path)));current.acceptance.forEach(a=>code.append(element('p',a.source+'：'+a.expected)));box.append(code);
  box.append(element('p','同功能画面对照'));const related=element('div','','related');manifest.pages.filter(p=>p.feature_id===current.feature_id).forEach(p=>related.append(action(p.title+' · '+kinds[p.kind],()=>{$('kindFilter').value='all';$('feature').value=current.feature_id;choose(p);$('detailsDialog').close();})));box.append(related);$('detailsDialog').showModal();
};
$('export').onclick=async()=>{
  const file=new File([JSON.stringify(bundle(),null,2)],manifest.project+'-review-'+new Date().toISOString().slice(0,10)+'.json',{type:'application/json'});
  if(navigator.canShare?.({files:[file]})) {try{await navigator.share({files:[file],title:manifest.title+' 评审批注'});return;}catch(e){if(e.name==='AbortError')return;}}
  const url=URL.createObjectURL(file),a=document.createElement('a');a.href=url;a.download=file.name;a.click();setTimeout(()=>URL.revokeObjectURL(url),30000);
};
$('import').onclick=()=>$('importFile').click();
$('importFile').onchange=async()=>{
  const file=$('importFile').files[0];if(!file)return;
  try{if(file.size>5_000_000)throw Error('文件过大');const incoming=validateBundle(JSON.parse(await file.text()),manifest.project);const merged=mergeAnnotations(annotations,incoming);if(save(merged))$('storageInfo').textContent='已合并导入；同一条批注保留较新修改，旧图批注不会覆盖到新图。';}
  catch(e){$('storageInfo').textContent='导入失败：'+e.message+'。现有批注未改动。';}finally{$('importFile').value='';}
};
window.addEventListener('beforeunload',e=>{if(draft&&$('comment').value.trim()){e.preventDefault();e.returnValue='';}});
window.addEventListener('hashchange',()=>{
  const page=manifest?.pages.find(p=>p.id===location.hash.slice(1));
  if(!page||page.id===current?.id)return;
  if(draft&&$('comment').value.trim()&&!confirm('当前批注未保存，放弃并切换画面？')){history.replaceState(null,'','#'+current.id);return;}
  document.querySelectorAll('dialog[open]').forEach(d=>d.close());
  $('feature').value='';$('kindFilter').value=page.kind==='design'?'all':'native';choose(page);
});
try {
  const response=await fetch('review.json',{cache:'no-store'});if(!response.ok)throw Error('无法读取评审项目');manifest=await response.json(); document.title=manifest.title+' · 评审'; $('projectTitle').textContent=manifest.title;
  manifest.features.forEach(f=>{const option=element('option',f.title);option.value=f.id;$('feature').append(option);});
  try {const stored=localStorage.getItem(keyFor(manifest.project));if(stored)annotations=validateBundle(JSON.parse(stored),manifest.project);storageReady=true;}
  catch{message('本地批注无法读取，暂不覆盖保存；请保留浏览器数据。',true);}
  const page=manifest.pages.find(p=>p.id===location.hash.slice(1))||manifest.pages.find(p=>p.kind!=='design')||manifest.pages[0];
  if(page.kind==='design')$('kindFilter').value='all';choose(page);
} catch(e) { message(e.message+'。请联网后刷新。',true);$('title').textContent='画面未能载入';document.querySelectorAll('button').forEach(b=>b.disabled=true); }
