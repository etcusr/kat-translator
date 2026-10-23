'use strict';
const platform=document.querySelector('#platform'),language=document.querySelector('#language'),gallery=document.querySelector('#gallery'),status=document.querySelector('#status');
const initial=new URLSearchParams(location.search).get('language');
if(['en','ru','es','tr'].includes(initial)) language.value=initial;
const labels={'07-voice':'Voice translation','08-image':'Image translation','01-voice':'Voice translation','02-text':'Text translation','03-languages':'Language picker','01-text':'Text translation','02-languages':'Language picker','03-settings':'Settings','04-models-and-voices':'Models and voices','05-voices':'Voices','06-quick-setup':'Quick setup','01-settings':'Settings','02-models-and-voices':'Models and voices','03-voices':'Voices','04-quick-setup':'Quick setup'};
fetch('../assets/screenshots/2026-10-22/manifest.json').then(r=>{if(!r.ok)throw Error('manifest');return r.json()}).then(data=>{
 function render(){
  const rows=data.captures.filter(r=>r.platform===platform.value&&r.language===language.value).sort((a,b)=>a.screen.localeCompare(b.screen));
  gallery.replaceChildren();gallery.classList.toggle('mac',platform.value==='macos-preview');
  status.textContent=rows.length+' images · '+(rows[0]?.version||'')+' · '+(platform.value==='ios'?'iPhone 17 Pro simulator screenshots':'Mac window screenshots + Quick setup view preview');
  for(const row of rows){
   const figure=document.createElement('figure'),a=document.createElement('a'),img=document.createElement('img'),caption=document.createElement('figcaption');
   a.href='../'+row.path;img.src=a.href;img.alt=(labels[row.screen]||row.screen)+' — '+row.language;img.loading='lazy';img.width=row.width;img.height=row.height;
   caption.textContent=(labels[row.screen]||row.screen)+' · '+row.width+' × '+row.height+(row.kind.startsWith('native view')?' · view preview':row.kind.startsWith('presentation fixture')?' · prepared example':'');
   a.append(img);figure.append(a,caption);gallery.append(figure);
  }
 }
 platform.addEventListener('change',render);language.addEventListener('change',render);render();
}).catch(()=>{status.textContent='Could not load the gallery. Serve this directory over HTTP, or open the PNG files listed in the manifest.'});
