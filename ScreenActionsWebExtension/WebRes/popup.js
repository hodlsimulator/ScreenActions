// popup.js — direct native calls; editor opens after tap; saves create items.
(() => {
  'use strict';

  const RT = (typeof chrome !== 'undefined' && chrome.runtime) ? chrome.runtime
           : (typeof browser !== 'undefined' && browser.runtime) ? browser.runtime
           : undefined;
  const TABS = (typeof chrome !== 'undefined' && chrome.tabs) ? chrome.tabs
            : (typeof browser !== 'undefined' && browser.tabs) ? browser.tabs
            : undefined;
  const SCR = (typeof chrome !== 'undefined' && chrome.scripting) ? chrome.scripting
           : (typeof browser !== 'undefined' && browser.scripting) ? browser.scripting
           : undefined;

  if (!RT) return;

  const el = (id)=>document.getElementById(id);
  const pad2=(n)=>String(n).padStart(2,'0');
  const toInputLocal=(d)=>`${d.getFullYear()}-${pad2(d.getMonth()+1)}-${pad2(d.getDate())}T${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
  const fromInputLocal=(s)=>{const d=new Date(s);return isNaN(d)?null:d.toISOString();};
  function setStatus(where,msg,ok){const n=el(where);if(!n)return;n.textContent=msg||'';n.classList.remove('ok','err');if(msg)n.classList.add(ok?'ok':'err');}
  function showView(name){for(const s of document.querySelectorAll('.view'))s.classList.remove('active');el(name)?.classList.add('active');}

  // BG read-only
  function bg(cmd,payload={}){ return RT.sendMessage({ cmd, ...payload }); }

  // Native (popup→native)
  const TIMEOUT_MS=15000;
  const isThenable=(x)=>!!x&&(typeof x==='object'||typeof x==='function')&&typeof x.then==='function';
  function withTimeout(p,ms){ let t; const k=new Promise((_,rej)=>{t=setTimeout(()=>rej(new Error('native timeout')),ms)}); return Promise.race([p,k]).finally(()=>clearTimeout(t)); }
  async function nativeCall(action,payload){
    const f=RT&&RT.sendNativeMessage; if(typeof f!=='function') throw new Error('sendNativeMessage not available');
    const msg={action,payload:payload||{}};
    try{const r=f(msg);if(isThenable(r))return await withTimeout(r,TIMEOUT_MS);}catch{}
    try{const r=f('',msg);if(isThenable(r))return await withTimeout(r,TIMEOUT_MS);}catch{}
    try{return await withTimeout(new Promise((res,rej)=>{try{f(msg,(out)=>{const le=chrome?.runtime?.lastError||null; if(le)rej(new Error(le.message||'Native callback error')); else res(out);});}catch(e){rej(e);}}),TIMEOUT_MS);}catch{}
    try{return await withTimeout(new Promise((res,rej)=>{try{f('',msg,(out)=>{const le=chrome?.runtime?.lastError||null; if(le)rej(new Error(le.message||'Native callback error')); else res(out);});}catch(e){rej(e);}}),TIMEOUT_MS);}catch{}
    throw new Error('Native bridge unavailable');
  }

  // Context
  let cachedCtx={selection:'',title:'',url:'',structured:undefined};
  async function getCtxFromBG(){try{const r=await bg('getPageCtx',{});if(r?.ok&&r.ctx)return r.ctx;}catch{}return null;}
  function pageProbe(){const selection=String(window.getSelection?.().toString()||'').slice(0,20000);const title=document.title||'';const url=location.href||'';return{selection,title,url,structured:undefined};}
  async function getCtxFallback(){try{const[tab]=await TABS.query({active:true,currentWindow:true});if(!tab?.id)return null;const[{result}]=await SCR.executeScript({target:{tabId:tab.id},func:pageProbe});return result||null;}catch{return null;}}
  async function ensureCtx(){const bgc=await getCtxFromBG();cachedCtx=bgc||await getCtxFallback()||cachedCtx;el('selText').textContent=cachedCtx.selection||cachedCtx.title||cachedCtx.url||'';}

  // Prefill/gather
  function fillEventFields(f){el('evTitle').value=f.title||'Event';const s=f.startISO?new Date(f.startISO):new Date();const e=f.endISO?new Date(f.endISO):new Date(Date.now()+3600_000);el('evStart').value=toInputLocal(s);el('evEnd').value=toInputLocal(e);el('evLocation').value=f.location||'';el('evInferTZ').checked=!!f.inferTZ;el('evAlert').value=(typeof f.alertMinutes==='number'&&f.alertMinutes>0)?String(f.alertMinutes):'';el('evNotes').value=f.notes||'';}
  function fillReminderFields(f){el('remTitle').value=f.title||'Todo';el('remHasDue').checked=!!f.hasDue;el('remDue').disabled=!el('remHasDue').checked;el('remDue').value=f.dueISO?toInputLocal(new Date(f.dueISO)):'';el('remNotes').value=f.notes||'';}
  function rowFor(listId,val,ph){const row=document.createElement('div');row.className='row';const input=document.createElement('input');input.type='text';input.value=val||'';input.placeholder=ph;const btn=document.createElement('button');btn.type='button';btn.textContent='✕';btn.addEventListener('click',()=>row.remove());row.appendChild(input);row.appendChild(btn);el(listId).appendChild(row);}
  function fillContactFields(f){el('ctGiven').value=f.givenName||'';el('ctFamily').value=f.familyName||'';el('emails').textContent='';(Array.isArray(f.emails)&&f.emails.length?f.emails:['']).forEach(e=>rowFor('emails',e,'name@example.com'));el('phones').textContent='';(Array.isArray(f.phones)&&f.phones.length?f.phones:['']).forEach(p=>rowFor('phones',p,'+353 1 234 5678'));el('ctStreet').value=f.street||'';el('ctCity').value=f.city||'';el('ctState').value=f.state||'';el('ctPostal').value=f.postalCode||'';el('ctCountry').value=f.country||'';}
  function fillCSV(text,csv){el('csvInput').value=text||'';el('csvOut').textContent=csv||'';}
  function gatherEventFields(){const title=el('evTitle').value.trim()||'Event';const startISO=fromInputLocal(el('evStart').value);const endISO=fromInputLocal(el('evEnd').value);const location=el('evLocation').value.trim();const inferTZ=el('evInferTZ').checked;const alertMinutes=el('evAlert').value?parseInt(el('evAlert').value,10):undefined;const notes=el('evNotes').value;return{title,startISO,endISO,location,inferTZ,alertMinutes,notes};}
  function gatherReminderFields(){const title=el('remTitle').value.trim()||'Todo';const hasDue=el('remHasDue').checked;const dueISO=hasDue?fromInputLocal(el('remDue').value):undefined;const notes=el('remNotes').value;return{title,hasDue,dueISO,notes};}
  function gatherContactFields(){const givenName=el('ctGiven').value.trim();const familyName=el('ctFamily').value.trim();const emails=Array.from(el('emails').querySelectorAll('input')).map(i=>i.value.trim()).filter(Boolean);const phones=Array.from(el('phones').querySelectorAll('input')).map(i=>i.value.trim()).filter(Boolean);return{givenName,familyName,emails,phones,street:el('ctStreet').value,city:el('ctCity').value,state:el('ctState').value,postalCode:el('ctPostal').value,country:el('ctCountry').value};}

  // Actions
  async function doPrepare(kind){const action=({event:'prepareEvent',reminder:'prepareReminder',contact:'prepareContact',csv:'prepareReceiptCSV',auto:'prepareAutoDetect'})[kind];return await nativeCall(action,cachedCtx||{});}

  async function init(){
    el('backEvent').addEventListener('click',()=>{showView('home');setStatus('statusEvent','');});
    el('backReminder').addEventListener('click',()=>{showView('home');setStatus('statusReminder','');});
    el('backContact').addEventListener('click',()=>{showView('home');setStatus('statusContact','');});
    el('backCSV').addEventListener('click',()=>{showView('home');setStatus('statusCSV','');});

    el('addEmail').addEventListener('click',()=>rowFor('emails','', 'name@example.com'));
    el('addPhone').addEventListener('click',()=>rowFor('phones','', '+353 1 234 5678'));

    el('btnAuto').addEventListener('click',async()=>{setStatus('statusHome','',true);try{const r=await doPrepare('auto');if(!r?.ok)return setStatus('statusHome',r?.message||'Failed.',false);const route=r.route; if(route==='event'){fillEventFields(r.fields||{});showView('event');} else if(route==='reminder'){fillReminderFields(r.fields||{});showView('reminder');} else if(route==='contact'){fillContactFields(r.fields||{});showView('contact');} else if(route==='csv'){fillCSV(cachedCtx?.selection||'',r.csv||'');showView('csv');}}catch(e){setStatus('statusHome',e.message||'Native error.',false);}});
    el('btnEvent').addEventListener('click',async()=>{setStatus('statusHome','',true);try{const r=await doPrepare('event');if(!r?.ok)return setStatus('statusHome',r?.message||'Failed.',false);fillEventFields(r.fields||{});showView('event');}catch(e){setStatus('statusHome',e.message||'Native error.',false);}});
    el('btnReminder').addEventListener('click',async()=>{setStatus('statusHome','',true);try{const r=await doPrepare('reminder');if(!r?.ok)return setStatus('statusHome',r?.message||'Failed.',false);fillReminderFields(r.fields||{});showView('reminder');}catch(e){setStatus('statusHome',e.message||'Native error.',false);}});
    el('btnContact').addEventListener('click',async()=>{setStatus('statusHome','',true);try{const r=await doPrepare('contact');if(!r?.ok)return setStatus('statusHome',r?.message||'Failed.',false);fillContactFields(r.fields||{});showView('contact');}catch(e){setStatus('statusHome',e.message||'Native error.',false);}});
    el('btnCSV').addEventListener('click',async()=>{setStatus('statusHome','',true);try{const r=await doPrepare('csv');if(!r?.ok)return setStatus('statusHome',r?.message||'Failed.',false);fillCSV(cachedCtx?.selection||'',r.csv||'');showView('csv');}catch(e){setStatus('statusHome',e.message||'Native error.',false);}});

    el('saveEvent').addEventListener('click',async()=>{setStatus('statusEvent','Saving…',true);try{const r=await nativeCall('saveEvent',{ fields:gatherEventFields() }); if(r?.ok){setStatus('statusEvent',r.message||'Saved.',true);window.close();} else setStatus('statusEvent',r?.message||'Failed.',false);}catch(e){setStatus('statusEvent',e.message||'Native error.',false);}});
    el('saveReminder').addEventListener('click',async()=>{setStatus('statusReminder','Saving…',true);try{const r=await nativeCall('saveReminder',{ fields:gatherReminderFields() }); if(r?.ok){setStatus('statusReminder',r.message||'Saved.',true);window.close();} else setStatus('statusReminder',r?.message||'Failed.',false);}catch(e){setStatus('statusReminder',e.message||'Native error.',false);}});
    el('saveContact').addEventListener('click',async()=>{setStatus('statusContact','Saving…',true);try{const r=await nativeCall('saveContact',{ fields:gatherContactFields() }); if(r?.ok){setStatus('statusContact',r.message||'Saved.',true);window.close();} else setStatus('statusContact',r?.message||'Failed.',false);}catch(e){setStatus('statusContact',e.message||'Native error.',false);}});

    el('reparseCSV').addEventListener('click',async()=>{setStatus('statusCSV','Parsing…',true);try{const text=el('csvInput').value||(cachedCtx?.selection||'');const r=await nativeCall('prepareReceiptCSV',{ selection:text, title:cachedCtx?.title||'', url:cachedCtx?.url||'' }); if(r?.ok){el('csvOut').textContent=r.csv||'';setStatus('statusCSV','Parsed.',true);} else setStatus('statusCSV',r?.message||'Failed.',false);}catch(e){setStatus('statusCSV',e.message||'Native error.',false);}});
    el('exportCSV').addEventListener('click',async()=>{setStatus('statusCSV','Exporting…',true);try{const csv=el('csvOut').textContent||'';const r=await nativeCall('exportReceiptCSV',{ csv }); if(r?.ok){setStatus('statusCSV',r.message||'Exported.',true);window.close();} else setStatus('statusCSV',r?.message||'Failed.',false);}catch(e){setStatus('statusCSV',e.message||'Native error.',false);}});

    await ensureCtx();
  }

  document.addEventListener('DOMContentLoaded', init);
})();
