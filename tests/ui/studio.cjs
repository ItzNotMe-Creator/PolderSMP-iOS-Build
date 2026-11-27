const {chromium}=require('playwright');
const assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({headless:true});
 try {
 const page=await browser.newPage({viewport:{width:1280,height:800}});
 const errors=[];page.on('pageerror',e=>errors.push(String(e)));
 await page.setContent('<style>[hidden]{display:none!important}body.locked #content{display:none}</style><aside><div class="brand">PolderSMP</div><nav><button data-view="Overzicht" aria-current="page">Overzicht</button><button data-view="Spelers">Spelers</button><button data-view="Dienstboek">Dienstboek</button><button data-view="Logs" hidden>Logs</button><button data-view="Bestanden" hidden>Bestanden</button><button data-view="Instellingen">Instellingen</button></nav></aside><main><div class="top"><h1 id="title"></h1><div id="sync"></div><button id="connection" hidden>Verbinding</button></div><form id="login"><h1>Inloggen</h1><input id="key"><button id="signin">Inloggen</button></form><div id="content"></div></main>');
 await page.evaluate(()=>{
 window.rows=[{name:'Proxy',proxy:true,status:'Online',live:{players:[]},routes:[{server:'SMP'}]},{name:'SMP',proxy:false,status:'Online',live:{players:[],tps:19.8}},{name:'Lobby',proxy:false,status:'Gestopt'}];
 window.activeServer='';window.clickCount=0;window.powerClicks=0;window.viewName='Overzicht';window.refresh=()=>{};window.overview=()=>{};
 window.render=function(){
 const content=document.querySelector('#content');
 content.replaceChildren();document.querySelectorAll('nav [data-view]').forEach(b=>b.setAttribute('aria-current',b.dataset.view===viewName?'page':'false'));
 if(viewName==='Spelers'){content.innerHTML='<div class="people"><details class="player"><summary>Alex · SMP</summary></details><details class="player"><summary>Sam · Lobby</summary></details></div>';return;}
 if(viewName!=='Overzicht')return;
 content.innerHTML='<section class="hero card"><div class="hero-top"><span class="role-chip">Mede-eigenaar</span></div><div class="kpi-grid"><div class="kpi"><strong>2/3</strong><small>Servers online</small></div></div></section><h2>Mijn servers</h2><p class="help">Tik op een server</p><div class="server-list"></div><div class="quick"><button>Meldkamer</button></div>';
 const list=content.querySelector('.server-list');rows.forEach(s=>{const section=document.createElement('section');section.className='server-section';const b=document.createElement('button');b.className='server-toggle';b.dataset.server=s.name;b.textContent=s.name;b.setAttribute('aria-expanded',String(activeServer===s.name));b.onclick=()=>{clickCount++;activeServer=activeServer===s.name?'':s.name;render()};section.append(b);if(activeServer===s.name){const power=document.createElement('button');power.textContent='Herstart';power.onclick=()=>powerClicks++;section.append(power)}list.append(section)});
 };document.querySelectorAll('nav [data-view]').forEach(b=>b.onclick=()=>{viewName=b.dataset.view;render()});
 render();
 });
 await page.addScriptTag({path:'shared/client-style.js'});
 assert.equal(await page.locator('.studio-server-node').count(),3);
 assert.equal(await page.locator('.studio-gauge b').innerText(),'2/3');
 await page.locator('.studio-server-node').filter({hasText:'SMP'}).click();
 assert.equal(await page.locator('.studio-selected .server-toggle').innerText(),'SMP');
 await page.getByRole('button',{name:'Herstart',exact:true}).click();
 assert.equal(await page.evaluate(()=>powerClicks),1);
 await page.getByRole('button',{name:'Zoeken',exact:true}).click();
 assert.equal(await page.locator('.studio-command-list button').filter({hasText:'Bestanden'}).count(),0);
 await page.locator('.studio-command-list button').filter({hasText:'Spelers'}).click();
 await page.locator('.studio-search').fill('Alex');
 assert.equal(await page.locator('.people details:visible').count(),1);
 await page.evaluate(()=>render());
 assert.equal(await page.locator('.studio-search').inputValue(),'Alex');
 await page.setViewportSize({width:390,height:844});
 assert.equal(await page.locator('.studio-mobile-more').isVisible(),true);
 await page.evaluate(()=>document.body.classList.add('locked'));
 assert.equal(await page.locator('aside').isVisible(),false);
 assert.deepEqual(errors,[]);
 console.log('PASS: dashboard, original controls, permission-aware menu, persistent search, mobile navigation, locked sidebar');
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exit(1)});
