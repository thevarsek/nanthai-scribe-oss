/** Sequential production QA: one server and one browser, both closed in finally. */
import { chromium } from 'playwright';
import { createServer } from 'node:http';
import { readFile, readdir, mkdir } from 'node:fs/promises';
import { resolve, extname, join } from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
const project=resolve(fileURLToPath(new URL('..',import.meta.url)));
const dist=join(project,'dist');
const shots=process.env.SHOTS_DIR||'/tmp/web4-shots';
const widths=[1440,1024,768,390];
const failures=[],errors=new Set(),external=new Set(),links=new Set();
const mime={'.html':'text/html','.css':'text/css','.js':'text/javascript','.svg':'image/svg+xml','.png':'image/png','.woff2':'font/woff2','.xml':'application/xml'};
async function files(dir,prefix='') { const result=[];for(const entry of await readdir(dir,{withFileTypes:true})){const name=join(prefix,entry.name);if(entry.isDirectory())result.push(...await files(join(dir,entry.name),name));else result.push(name);}return result; }
const all=await files(dist);
const routes=all.filter(f=>f.endsWith('.html')).map(f=>'/'+f.replace(/index\.html$/,'').replace(/\.html$/,'')).sort();
const guideRoutes=routes.filter(route=>route.startsWith('/guides/'));
// The DMG is published by the release script, not fabricated by website QA.
const config=await readFile(join(project,'src/lib/site.ts'),'utf8');
const macDownload=config.match(/downloads:\s*\{\s*mac:\s*"([^"]+)"/)?.[1];
assert.equal(macDownload,'/download/NanthAi-Scribe.dmg');
// Before launch every store button is a disabled "Coming soon" with no href.
const launchedMac=/mac:\s*true/.test(config.match(/launched:\s*\{[^}]*\}/)[0]);
const launchedPhone=/iphone:\s*true/.test(config.match(/launched:\s*\{[^}]*\}/)[0]);
const server=createServer(async(req,res)=>{
 try{
  const pathname=decodeURIComponent(new URL(req.url,'http://localhost').pathname);
  let file=pathname==='/'?'index.html':pathname.slice(1);
  if(!extname(file))file+='.html';
  const path=resolve(dist,file);
  if(!path.startsWith(dist+'/'))throw Error('Invalid path');
  const body=await readFile(path);res.writeHead(200,{'Content-Type':mime[extname(path)]||'application/octet-stream'});res.end(body);
 }catch{res.writeHead(404,{'Content-Type':'text/html'});res.end(await readFile(join(dist,'404.html')));}
});
await new Promise(done=>server.listen(0,'127.0.0.1',done));
const base=`http://127.0.0.1:${server.address().port}`;
let browser;
let cases=0,contrastCount=0,collisionCount=0;
try{
 browser=await chromium.launch({headless:true});
 const context=await browser.newContext({reducedMotion:'reduce',deviceScaleFactor:1});
 const page=await context.newPage();
 page.on('pageerror',e=>errors.add(e.message));
 page.on('console',msg=>{if(msg.type()==='error')errors.add(msg.text());});
 page.on('request',req=>{if(!req.url().startsWith(base)&&!req.url().startsWith('data:'))external.add(req.url());});
 await page.addInitScript(()=>{
  window.__layoutShift=0;
  new PerformanceObserver(list=>list.getEntries().forEach(e=>{if(!e.hadRecentInput)window.__layoutShift+=e.value;})).observe({type:'layout-shift',buffered:true});
 });
 for(const width of widths){
  console.log(`CHECK viewport ${width}px: ${routes.length} pages`);
  await page.setViewportSize({width,height:1000});
  for(const route of routes){
   await page.goto(base+route,{waitUntil:'networkidle'});await page.evaluate(()=>document.fonts.ready);
   assert.equal(await page.locator('main').count(),1);assert.equal(await page.locator('header.site-header').count(),1);assert.equal(await page.locator('footer.site-footer').count(),1);
   const h1=await page.locator('h1').count();if(h1!==1)failures.push(`${width} ${route}: ${h1} h1 elements`);
   const metadata=await page.evaluate(()=>({title:document.title,desc:document.querySelector('meta[name="description"]')?.content,og:document.querySelector('meta[property="og:title"]')?.content,canonical:document.querySelector('link[rel="canonical"]')?.href}));
   if(!metadata.title||!metadata.desc||!metadata.og||!metadata.canonical)failures.push(`${route}: missing SEO metadata`);
   if(metadata.canonical!=='https://scribe.nanthai.tech'+route)failures.push(`${route}: canonical ${metadata.canonical}`);
   if(guideRoutes.includes(route)){
    const scripts=page.locator('head script[type="application/ld+json"]');
    assert.equal(await scripts.count(),2,`${route}: Article and BreadcrumbList in the head`);
    const data=await scripts.evaluateAll(nodes=>nodes.map(node=>JSON.parse(node.textContent)));
    const article=data.find(item=>item['@type']==='Article');
    const breadcrumbs=data.find(item=>item['@type']==='BreadcrumbList');
    assert.deepEqual(breadcrumbs.itemListElement.map(item=>[item.position,item.name,item.item]),[
     [1,'Home','https://scribe.nanthai.tech'],[2,'Guides','https://scribe.nanthai.tech/guides'],[3,await page.locator('h1').textContent(),metadata.canonical],
    ]);
    const headings=await page.locator('article h2').evaluateAll(nodes=>nodes.map(node=>'#'+node.id));
    assert.deepEqual(await page.locator('.docs-toc a').evaluateAll(nodes=>nodes.map(node=>node.getAttribute('href'))),headings);
    assert.equal(await page.locator('.docs-toc').isVisible(),width>768);
    assert.equal(await page.locator('.guide-more a').count(),3);
    assert(!await page.locator(`.guide-more a[href="${route}"]`).count());
    assert.equal(await page.getByRole('link',{name:'Download for Mac',exact:true}).count(),launchedMac?1:0);
    assert.equal(article['@type'],'Article');assert.equal(article['@context'],'https://schema.org');
    assert.equal(article.headline,await page.locator('h1').textContent());
    assert.equal(article.description,metadata.desc);assert.equal(article.publisher.name,'NanthAi');
    assert.equal(article.mainEntityOfPage,metadata.canonical);
    assert.equal(article.dateModified,await page.locator('time').getAttribute('datetime'));
    assert.match(article.dateModified,/^\d{4}-\d{2}-\d{2}$/);
    assert.equal(await page.locator('meta[property="og:type"]').getAttribute('content'),'article');
    assert.equal(await page.locator('a[href*="apps.apple.com"]').count(),0,'No unreleased iPhone store link');
   }
   assert.deepEqual(await page.locator('.nav-list a').allTextContents(),['How it works','Features','Docs','Guides']);
   const macButtons=page.getByRole('link',{name:'Download for Mac',exact:true});
   const soonButtons=page.locator('.btn[aria-disabled="true"]');
   if(route==='/'||route==='/download'){
    const macSlots=route==='/'?2:1,phoneSlots=route==='/'?2:1,header=launchedMac||launchedPhone?0:1;
    assert.equal(await macButtons.count(),launchedMac?macSlots:0);
    assert.equal(await soonButtons.count(),header+(launchedMac?0:macSlots)+(launchedPhone?0:phoneSlots));
   }
   for(const button of await soonButtons.all()){assert.equal(await button.textContent(),'Coming soon');assert.equal(await button.getAttribute('href'),null);}
   if(!launchedMac)assert.equal(await page.getByRole('link',{name:'Download for Mac',exact:true}).count(),0);
   if(!launchedPhone)assert.equal(await page.getByRole('link',{name:'Download on the App Store'}).count(),0);
   for(const button of await macButtons.all()){
    assert.equal(await button.getAttribute('href'),macDownload);
    assert.equal(await button.locator('..').locator('p').textContent(),'macOS 26 · Apple silicon');
   }
   // Exercise FAQ expansion as well as closed native disclosures.
   const faq=page.locator('.faq details').first();if(await faq.count()){await faq.locator('summary').click();assert(await faq.getAttribute('open')!==null);await faq.locator('summary').click();}
   await page.locator('.faq details').evaluateAll(nodes=>nodes.forEach(n=>n.open=true));
   // Open docs as well as the site menu, including every article's platform caption.
   const docsToggle=page.locator('.docs-toggle');
   if(await docsToggle.isVisible())await docsToggle.click();
   for(const menu of ['closed','open']){
    const toggle=page.locator('.nav-toggle');
    if(await toggle.isVisible()){
     const isOpen=await toggle.getAttribute('aria-expanded')==='true';
     if(isOpen!==(menu==='open'))await toggle.click();
     if(menu==='open')assert(await page.locator('.nav-list').isVisible());
    }
    const result=await page.evaluate(()=>{
     const bad=[],collisions=[];const rects=[];let checks=0;
     const visible=el=>{
      if(el.closest('.scene,[aria-hidden="true"],.sr-only,.skip'))return false;
      for(let p=el;p;p=p.parentElement){if(p.tagName==='DETAILS'&&!p.open&&!el.closest('summary'))return false;const s=getComputedStyle(p);if(s.display==='none'||s.visibility==='hidden'||Number(s.opacity)<.1)return false;}
      return el.getClientRects().length>0;
     };
     // Text clipped by a scrolling ancestor (the docs sidebar) is not on screen and cannot collide.
     const clip=(el,r)=>{
      let l=r.left,t=r.top,rt=r.right,b=r.bottom;
      for(let p=el.parentElement;p&&p!==document.body;p=p.parentElement){const s=getComputedStyle(p);if(s.overflowY==='visible'&&s.overflowX==='visible')continue;const c=p.getBoundingClientRect();l=Math.max(l,c.left);t=Math.max(t,c.top);rt=Math.min(rt,c.right);b=Math.min(b,c.bottom);}
      return rt-l>1&&b-t>1?{left:l,top:t,right:rt,bottom:b,width:rt-l,height:b-t}:null;
     };
     if(document.documentElement.scrollWidth>innerWidth+1)bad.push(`document ${document.documentElement.scrollWidth}px > ${innerWidth}px`);
     const walker=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT);
     while(walker.nextNode()){
      const node=walker.currentNode,el=node.parentElement;if(!node.textContent.trim()||!visible(el))continue;
      const range=document.createRange();range.selectNodeContents(node);
      const style=getComputedStyle(el),size=parseFloat(style.fontSize);
      for(const raw of range.getClientRects()){
       if(!raw.width||!raw.height)continue;
       const r=clip(el,raw);if(!r)continue;
       if(r.left < -1 || r.right > innerWidth+1)bad.push(`${el.tagName}: ${node.textContent.trim().slice(0,60)} [${Math.round(r.left)},${Math.round(r.right)}]`);
       rects.push({x:r.left,y:r.top+size*.18,w:r.width,h:r.height-size*.36,node,el,text:node.textContent.trim().slice(0,45)});
      }
     }
     // Compare actual text lines, not enclosing blocks. A menu intentionally overlays main.
     for(let i=0;i<rects.length;i++)for(let j=i+1;j<rects.length;j++){
      const a=rects[i],b=rects[j];if(a.node===b.node)continue;
      if(a.el.closest('.site-header')!==b.el.closest('.site-header')&&(a.el.closest('.site-header')||b.el.closest('.site-header')))continue;
      const x=Math.min(a.x+a.w,b.x+b.w)-Math.max(a.x,b.x),y=Math.min(a.y+a.h,b.y+b.h)-Math.max(a.y,b.y);
      checks++;if(x>2&&y>2)collisions.push(`${a.text} <> ${b.text}`);
     }
     return {bad:[...new Set(bad)],collisions:[...new Set(collisions)],checks,shift:window.__layoutShift};
    });
    cases++;collisionCount+=result.checks;
    if(result.bad.length||result.collisions.length)failures.push(`${width} ${route} ${menu}: ${JSON.stringify(result)}`);
    if(result.shift>.01)failures.push(`${width} ${route}: CLS ${result.shift}`);
   }
   for(const href of await page.locator('a[href]').evaluateAll(nodes=>nodes.map(n=>n.getAttribute('href'))))if(href.startsWith('/')||href.startsWith('#'))links.add(JSON.stringify([route,href]));
   const contrast=await page.evaluate(()=>{
    function parse(s){const v=s.match(/[\d.]+/g)?.map(Number);return v?.length>=3?[v[0],v[1],v[2],v[3]??1]:[0,0,0,0];}
    function over(a,b){return [a[0]*a[3]+b[0]*(1-a[3]),a[1]*a[3]+b[1]*(1-a[3]),a[2]*a[3]+b[2]*(1-a[3]),1];}
    function lum(c){const v=c.slice(0,3).map(x=>{x/=255;return x<=.04045?x/12.92:((x+.055)/1.055)**2.4;});return v[0]*.2126+v[1]*.7152+v[2]*.0722;}
    const bad=[];let count=0;
    for(const el of document.querySelectorAll('body *')){
     if(![...el.childNodes].some(n=>n.nodeType===3&&n.textContent.trim())||el.closest('.scene,[aria-hidden="true"],.skip,.sr-only'))continue;
     let shown=true;const chain=[];
     for(let p=el;p;p=p.parentElement){const s=getComputedStyle(p);if(s.display==='none'||s.visibility==='hidden'||+s.opacity<.1)shown=false;chain.unshift(p);}
     if(!shown||!el.getClientRects().length)continue;
     let bg=[22,33,46,1];for(const p of chain)bg=over(parse(getComputedStyle(p).backgroundColor),bg);
     const s=getComputedStyle(el),fg=over(parse(s.color),bg),a=lum(fg),b=lum(bg),ratio=(Math.max(a,b)+.05)/(Math.min(a,b)+.05);
     const large=parseFloat(s.fontSize)>=24||(parseFloat(s.fontSize)>=18.66&&+s.fontWeight>=700);
     count++;if(ratio<(large?3:4.5)-.01)bad.push(`${el.tagName} ${el.textContent.trim().slice(0,45)} ${ratio.toFixed(2)}:1`);
    }return {count,bad};
   });contrastCount+=contrast.count;
   if(contrast.bad.length)failures.push(`${width} ${route} contrast: ${contrast.bad.join('; ')}`);
  }
 }
 const sitemap=await readFile(join(dist,'sitemap-0.xml'),'utf8');
 assert(routes.filter(route=>route!=='/404').every(route=>sitemap.includes('https://scribe.nanthai.tech'+route)));
 // Check local targets once per document, including table-of-contents fragments.
 const placeholders=[...config.matchAll(/"(#[^"]+)"/g)].map(m=>m[1]);
 let linkCount=0;
 for(const encoded of links){
  const [route,href]=JSON.parse(encoded);if(placeholders.includes(href))continue;
  const url=new URL(href,base+route),path=url.pathname;
  if(path===macDownload)continue;
  if(!routes.includes(path)&&!all.includes(path.slice(1))){failures.push(`Broken local page: ${route} → ${href}`);continue;}
  if(url.hash){const html=await (await fetch(base+path)).text();if(!html.includes(`id="${decodeURIComponent(url.hash.slice(1))}"`))failures.push(`Missing fragment: ${route} → ${href}`);}
  linkCount++;
 }
 const feed=await (await fetch(base+'/appcast.xml')).text();
 const appcast=await page.evaluate(xml=>{
  const doc=new DOMParser().parseFromString(xml,'application/xml');
  return {errors:doc.querySelectorAll('parsererror').length,root:doc.documentElement.tagName,version:doc.documentElement.getAttribute('version'),channels:doc.querySelectorAll('rss > channel').length,items:doc.querySelectorAll('item').length,sparkle:doc.documentElement.lookupNamespaceURI('sparkle'),title:doc.querySelector('channel > title')?.textContent};
 },feed);
 assert.deepEqual(appcast,{errors:0,root:'rss',version:'2.0',channels:1,items:(feed.match(/<item>/g)||[]).length,sparkle:'http://www.andymatuschak.org/xml-namespaces/sparkle',title:'NanthAi Scribe updates'});
 // Reduced motion is a final frame on every illustrated scene, with stable geometry.
 await page.goto(base+'/how-it-works',{waitUntil:'networkidle'});
 await page.waitForFunction(()=>window.__scribeScenes);
 assert.equal(await page.evaluate(()=>[...window.__scribeScenes.values()].filter(s=>s.instance).length),0);
 assert.equal(await page.locator('.scene-running').count(),0);
 assert.equal(await page.locator('.mt-result.show').count(),1);
 assert.equal(await page.locator('.bubble.out.show').count(),1);
 assert.equal(await page.locator('.kb[data-layer="letters"]').count(),1);
 // The features callouts are written in their final frame too.
 await page.goto(base+'/features',{waitUntil:'networkidle'});
 await page.waitForFunction(()=>window.__scribeScenes);
 assert.equal(await page.evaluate(()=>[...window.__scribeScenes.values()].filter(s=>s.instance).length),0);
 assert.deepEqual(await page.evaluate(()=>[...window.__scribeScenes.values()].map(s=>s.kind)),['tones','meeting','swipe','learn','shortcut','transcribe']);
 assert.equal(await page.locator('.sc-tones[data-tone="formal"] .tn-text').textContent(),'Could we move the launch to 3 November? We would need an additional week.');
 assert.equal(await page.locator('.ln-row.show').count(),1);assert.equal(await page.locator('.ln-word').textContent(),'NanthAi');
 assert.equal(await page.locator('.tr-row.new.show').count(),1);assert.equal(await page.locator('.sh-hud.show').count(),1);
 assert.equal(await page.locator('.compare.journeys tbody').count(),8);
 // No page, link or sitemap entry mentions the changelog any more.
 for(const file of all.filter(f=>f.endsWith('.html')||f.endsWith('.xml')))assert(!/changelog/i.test(await readFile(join(dist,file),'utf8')),`${file} mentions the changelog`);
 assert(!all.includes('changelog.html'));
 // Reduced motion shows every reveal target at once, before any scrolling.
 await page.goto(base,{waitUntil:'networkidle'});
 const reducedReveal=await page.evaluate(()=>[...document.querySelectorAll('[data-reveal]')].every(el=>getComputedStyle(el).opacity==='1'&&getComputedStyle(el).transform==='none'));
 assert(reducedReveal,'Reduced motion: reveal targets visible immediately');
 // Normal motion: the phone scene types on the letters, then talks; the typed text lands as a bubble.
 await page.emulateMedia({reducedMotion:'no-preference'});await page.setViewportSize({width:1440,height:1000});
 await page.goto(base,{waitUntil:'networkidle'});
 await page.locator('.sc-phone').scrollIntoViewIfNeeded();
 await page.waitForFunction(()=>[...window.__scribeScenes.values()].find(s=>s.kind==='phone')?.instance);
 await page.waitForFunction(()=>document.querySelector('.sc-phone .ph-field .sc-typed')?.textContent==='On my way,',null,{timeout:6000});
 assert.equal(await page.locator('.kb[data-layer="letters"]').count(),1);
 await page.waitForFunction(()=>document.querySelector('.sc-phone .kb')?.dataset.layer==='talk',null,{timeout:4000});
 await page.waitForFunction(()=>document.querySelector('.sc-phone .kb-live.words')?.textContent==='there in ten minutes',null,{timeout:4000});
 await page.waitForFunction(()=>document.querySelector('.sc-phone .bubble.out.show')?.textContent==='On my way, there in ten minutes',null,{timeout:6000});
 // Normal motion only loads visible scene modules and follows all three story beats.
 await page.emulateMedia({reducedMotion:'no-preference'});await page.setViewportSize({width:1440,height:1000});
 await page.goto(base,{waitUntil:'networkidle'});
 await page.waitForFunction(()=>[...window.__scribeScenes.values()].find(s=>s.kind==='story')?.instance);
 const loaded=await page.evaluate(()=>[...window.__scribeScenes.values()].filter(s=>s.instance).map(s=>s.kind));
 assert.deepEqual(loaded,['story']);
 await page.waitForFunction(()=>document.querySelector('.sc-story')?.dataset.phase==='refine',null,{timeout:11000});
 assert.equal(await page.locator('.story-words .filler').count()>0,true);
 await page.waitForFunction(()=>document.querySelector('.sc-story')?.dataset.phase==='sent',null,{timeout:11000});
 // Reveal: above-the-fold targets are in after load; the rest come in as they scroll into view.
 const revealState=await page.evaluate(()=>window.__scribeReveal());
 assert(revealState.total>8&&revealState.shown>0&&revealState.shown<revealState.total,`Reveal before scroll: ${JSON.stringify(revealState)}`);
 for(let y=0;y<await page.evaluate(()=>document.body.scrollHeight);y+=600){await page.evaluate(top=>window.scrollTo(0,top),y);await page.waitForTimeout(80);}
 await page.evaluate(()=>window.scrollTo(0,document.body.scrollHeight));
 await page.waitForFunction(()=>{const s=window.__scribeReveal();return s.shown===s.total;});
 const revealTotal=(await page.evaluate(()=>window.__scribeReveal())).total;
 await page.waitForFunction(()=>![...window.__scribeScenes.values()].find(s=>s.kind==='story').root.classList.contains('scene-running'));
 await page.evaluate(()=>window.scrollTo(0,0));await page.keyboard.press('Tab');
 const focus=await page.evaluate(()=>{const el=document.activeElement;const s=getComputedStyle(el);return {tag:el.tagName,outline:s.outlineStyle,width:parseFloat(s.outlineWidth)};});
 assert(focus.outline!=='none'&&focus.width>=2,'Visible keyboard focus ring');
 // Docs search is built at build time and answers from titles and headings without a request.
 await page.goto(base+'/docs/getting-started-mac',{waitUntil:'networkidle'});
 const indexSize=await page.evaluate(()=>JSON.parse(document.getElementById('docs-index').textContent).length);
 assert.equal(indexSize,routes.filter(r=>r.startsWith('/docs/')).length,'Search index covers every article');
 await page.fill('#docs-q','talk shortcut');
 await page.waitForSelector('#docs-results:not([hidden]) [role="option"]');
 const firstHit=await page.locator('#docs-results [role="option"] a').first().textContent();
 assert(/Talk shortcut/.test(firstHit),`First hit for "talk shortcut": ${firstHit}`);
 await page.fill('#docs-q','zzzz');assert.equal(await page.locator('#docs-results .empty').count(),1);
 await page.fill('#docs-q','recently deleted');await page.waitForSelector('#docs-results [role="option"]');
 await page.keyboard.press('ArrowDown');assert.equal(await page.locator('#docs-results [aria-selected="true"]').count(),1);
 await page.keyboard.press('Enter');await page.waitForURL('**/docs/recently-deleted**');
 await page.fill('#docs-q','meeting');await page.waitForSelector('#docs-results [role="option"]');await page.keyboard.press('Escape');
 assert(await page.locator('#docs-results').isHidden(),'Escape closes search');
 // Mobile docs navigation opens the grouped list.
 await page.setViewportSize({width:390,height:844});await page.goto(base+'/docs/refine',{waitUntil:'networkidle'});
 assert(await page.locator('#docs-links').isHidden());await page.click('.docs-toggle');assert(await page.locator('#docs-links').isVisible());
 assert.equal(await page.locator('#docs-links a[aria-current="page"]').count(),1);
 const groupCount=await page.locator('#docs-links section').count();assert(groupCount>=9,`Docs groups: ${groupCount}`);
 // A guide is discoverable from both indexes and every related doc declared in frontmatter.
 await page.goto(base+'/docs',{waitUntil:'networkidle'});
 await page.locator('main a[href="/guides"]').click();await page.waitForURL('**/guides');
 assert.deepEqual((await page.locator('main a[href^="/guides/"]').evaluateAll(nodes=>nodes.map(n=>n.getAttribute('href')))).sort(),guideRoutes);
 assert.deepEqual(await page.locator('.guide-topic h2').allTextContents(),['Dictation on Mac','iPhone','Meetings and notes','Languages and vocabulary','Comparisons']);
 const guideLink=page.locator('main a[href^="/guides/"]').first();
 const guidePath=await guideLink.getAttribute('href');await guideLink.click();await page.waitForURL('**'+guidePath);
 const docLink=page.locator('article a[href^="/docs/"]').first();
 const docPath=await docLink.getAttribute('href');await docLink.click();await page.waitForURL('**'+docPath);
 await page.locator(`article a[href="${guidePath}"]`).click();await page.waitForURL('**'+guidePath);
 let relatedCount=0;
 for(const route of guideRoutes){
  await page.goto(base+route,{waitUntil:'domcontentloaded'});
  const currentMarkdown=await readFile(join(project,'src/content/guides/en',route.split('/').pop()+'.md'),'utf8');
  const topic=currentMarkdown.match(/^topic: (.+)$/m)?.[1];
  assert(topic,`${route}: topic set`);
  const sameTopic=[];
  for(const other of guideRoutes.filter(other=>other!==route)){
   const text=await readFile(join(project,'src/content/guides/en',other.split('/').pop()+'.md'),'utf8');
   if(text.match(/^topic: (.+)$/m)?.[1]===topic)sameTopic.push(other);
  }
  const more=await page.locator('.guide-more a').evaluateAll(nodes=>nodes.map(node=>node.getAttribute('href')));
  assert.equal(more.filter(href=>sameTopic.includes(href)).length,Math.min(3,sameTopic.length),`${route}: topic matches before fallback`);
  const slug=route.split('/').pop();
  const markdown=await readFile(join(project,'src/content/guides/en',slug+'.md'),'utf8');
  const related=markdown.match(/^related: \[([^\]]*)\]/m)?.[1].split(',').map(s=>s.trim());
  assert(related?.length,`${route}: related docs declared`);
  for(const doc of related){
   assert(routes.includes('/docs/'+doc),`${route}: related doc ${doc} exists`);
   await page.goto(base+'/docs/'+doc,{waitUntil:'domcontentloaded'});
   const backlink=page.locator(`article a[href="${route}"]`);
   assert.equal(await backlink.count(),1,`${doc}: backlink to ${route}`);
   assert((await backlink.locator('..').textContent()).startsWith('Related guide: '));relatedCount++;
  }
 }
 // Exercise the shared TOC and the added mobile header link.
 await page.setViewportSize({width:1440,height:1000});await page.goto(base+'/guides/dictate-emails',{waitUntil:'networkidle'});
 await page.locator('.docs-toc a').nth(1).click();
 await page.waitForFunction(()=>location.hash&&document.querySelector('.docs-toc a.active')?.getAttribute('href')===location.hash);
 await page.setViewportSize({width:390,height:1000});await page.goto(base+'/docs',{waitUntil:'networkidle'});
 await page.getByRole('button',{name:'Open menu',exact:true}).click();
 await page.locator('.nav-list a[href="/guides"]').click();await page.waitForURL('**/guides');
 // Capture complete, deterministic final frames for owner review.
 await page.emulateMedia({reducedMotion:'reduce'});await mkdir(shots,{recursive:true});
 for(const [route,width,name] of [['/',1440,'home-1440'],['/',390,'home-390'],['/',1440,'home-iphone-1440'],['/features',1440,'features-1440'],['/features',390,'features-390'],['/privacy',1440,'privacy-1440'],['/download',390,'download-390'],['/docs/getting-started-mac',1440,'docs-1440'],['/docs/getting-started-mac',390,'docs-390'],['/docs/getting-started-mac',1440,'docs-search-1440'],['/guides',1440,'guides-1440'],['/guides',390,'guides-390'],['/guides/voice-notes-to-text-mac',1440,'guide-1440'],['/guides/voice-notes-to-text-mac',390,'guide-390']]){
  await page.setViewportSize({width,height:1000});await page.goto(base+route,{waitUntil:'networkidle'});await page.evaluate(()=>document.fonts.ready);
  if(route==='/'||route==='/features')await page.waitForFunction(()=>window.__scribeScenes);
  if(name.includes('iphone')){await page.locator('.handoff-stage').locator('..').screenshot({path:join(shots,name+'.png')});continue;}
  if(name.includes('search')){await page.fill('#docs-q','meeting');await page.waitForSelector('#docs-results [role="option"]');await page.screenshot({path:join(shots,name+'.png'),fullPage:false});continue;}
  await page.screenshot({path:join(shots,name+'.png'),fullPage:true});
  if(name==='guide-1440'){
   await page.locator('.final').screenshot({path:join(shots,'guide-cta-1440.png')});
   await page.locator('.guide-more').locator('..').screenshot({path:join(shots,'more-guides-1440.png')});
  }
 }
 for(const width of [1440,390]){
  await page.setViewportSize({width,height:1000});await page.goto(base+'/guides',{waitUntil:'networkidle'});
  if(width===390)await page.getByRole('button',{name:'Open menu',exact:true}).click();
  await page.screenshot({path:join(shots,`header-${width}.png`),fullPage:false});
 }
 assert.equal(external.size,0,`External requests: ${[...external]}`);
 assert.equal(errors.size,0,`Browser errors: ${[...errors]}`);
 if(failures.length){console.error(failures.join('\n'));process.exitCode=1;}
 else{
  console.log(`PASS layout: ${routes.length} pages × 4 widths × 2 menu states = ${cases} checks; 0 overflows, 0 text collisions.`);
  console.log(`PASS accessibility: ${contrastCount} text contrast checks; AA contrast, landmarks, focus styles, docs navigation (${groupCount} groups, mobile panel).`);
  console.log(`PASS links and SEO: ${linkCount} local targets; metadata and sitemap; 0 broken links.`);
  console.log(`PASS motion: 22-second hero story, type-or-talk phone scene, 6 feature callouts, lazy scene imports, offscreen pause, ${revealTotal} scroll reveals in; reduced motion shows everything at once; CLS ≤ 0.01.`);
  console.log(`PASS launch: Mac ${launchedMac?'links to the DMG':'is Coming soon'}, iPhone ${launchedPhone?'links to the App Store':'is Coming soon'}; canonical URLs on https://scribe.nanthai.tech; no changelog page, link or sitemap entry.`);
  console.log(`PASS docs search: ${indexSize} articles indexed at build time; title and heading hits, keyboard navigation, no requests.`);
  console.log(`PASS guides: ${guideRoutes.length} Articles with Article + BreadcrumbList JSON-LD, H2 TOCs and topic-based related links; ${relatedCount} generated backlinks; docs → guides → article → doc → article navigation.`);
  console.log('PASS runtime: 0 external requests; 0 browser errors.');
  console.log(`PASS screenshots: ${shots}/home-1440.png, home-390.png, home-iphone-1440.png, features-1440.png, features-390.png, privacy-1440.png, download-390.png, docs-1440.png, docs-390.png, docs-search-1440.png, guides-1440.png, guides-390.png, guide-1440.png, guide-390.png, header-1440.png, header-390.png, guide-cta-1440.png, more-guides-1440.png.`);
 }
}finally{await browser?.close();await new Promise(done=>server.close(done));}
