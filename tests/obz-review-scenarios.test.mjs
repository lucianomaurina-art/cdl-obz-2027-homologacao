import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const html=fs.readFileSync(new URL('../index.html',import.meta.url),'utf8');
const js=html.split('<script>')[1]?.split('</script>')[0];
assert.ok(js,'Script OBZ não localizado');

test('interface: colunas de esforço máximo e dois cenários por rubrica',()=>{
 for(const text of ['Esforço máximo','Cenário intermediário','Cenário severo','Consequência do ajuste','Salvar todas as alterações','Justificativa e meses','Replicar janeiro']){
  assert.ok(html.includes(text),'Texto obrigatório ausente: '+text)
 }
 assert.match(html,/id="lines"/);
 assert.match(html,/id="reviewSaveAll"/);
 assert.match(html,/id="reviewSaveBottom"/);
});
test('integração: carrega cenários e carimbo de versão do banco',()=>{
 assert.match(js,/from\('obz_line_scenarios'\)/);
 assert.match(js,/source_key,updated_at/);
 assert.match(js,/scenario_updated_at/);
 assert.match(js,/obz_save_line_scenario_reviews/);
});
test('JavaScript compilável e controles distintos para base oficial e cenários',()=>{
 assert.doesNotThrow(()=>new Function(js));
 assert.match(html,/id="baseRepeatJanuary"/);
 assert.match(html,/id="baseUndoJanuary"/);
 assert.match(js,/reviewChanges\(\)\.length/);
});
function scenarioLogic(initial,jan=90,baseJan=100){
 const start=js.indexOf('function reviewRound('),stop=js.indexOf('function reviewScenarioOptions(',start);
 assert.ok(start>0&&stop>start);
 const input={
  id:'id-1',description:'Testes',category:'expense',
  months:[baseJan,120,80,130,100,90,110,100,120,80,90,100],
  intermediate_action:'reduzir',
  intermediate_annual:null,
  intermediate_months:null
 };
 const fields=['intermediate_action','intermediate_annual','intermediate_months','intermediate_consequence'];
 const tr={querySelector:()=>null,classList:{toggle:()=>{}}};
 const nodes={
  '[data-line-id="id-1"]':tr,
  '[data-review-undo="id-1:intermediate"]':{disabled:false}
 };
 let selected=null,draft=null;
 const ctx={
  REVIEW_FIELDS:fields,reviewDrafts:new Map(),reviewUndo:new Map(),
  reviewEditable:()=>true,reviewValue:(x,key)=>draft&&key in draft?draft[key]:x[key],
  reviewLineDirty:()=>true,reviewRefreshCounts:()=>{},reviewStatusText:()=>'',renderLines:()=>{},
  notice:(message)=>{ctx.error=message},
  confirm:message=>{ctx.confirmed=message;return true},
  $:()=>({textContent:''}),
  br:v=>'R$ '+v.toFixed(2),
  document:{querySelector:selector=>nodes[selector]||null},
  annual:x=>x.months.reduce((a,b)=>a+b,0),
 };
 vm.runInNewContext(js.slice(start,stop),ctx);
 draft={intermediate_action:'reduzir',intermediate_months:[jan,...input.months.slice(1)],intermediate_annual:input.months.reduce((a,b)=>a+b,0)};
 ctx.reviewMutate=(x,k,v)=>{draft[k]=v;draft.intermediate_annual=v.reduce((a,b)=>a+b,0).toFixed(2);selected=v};
 ctx.reviewReplicateJanuary(input,'intermediate',initial);
 return {result:selected,ctx,input}
}
test('replicar mesma variação percentual conserva sazonalidade',()=>{
 const {result,ctx}=scenarioLogic('ratio',90);
 assert.equal(result[0],90);assert.equal(result[1],108);assert.equal(result[2],72);
 assert.equal(result[3],117);assert.ok(ctx.confirmed.includes('Total anual proposto'));
});
test('replicar valor de janeiro ignora sazonalidade apenas quando solicitado',()=>{
 const {result}=scenarioLogic('value',90);
 assert.equal(result.length,12);assert.ok(result.every(x=>x===90))
});
test('replicar diferença absoluta conserva o desvio de R$10 em cada mês',()=>{
 const {result}=scenarioLogic('delta',90);
 assert.equal(result[0],90);assert.equal(result[1],110);assert.equal(result[2],70)
});
test('sem base de janeiro não calcula percentual artificial',()=>{
 const {result,ctx}=scenarioLogic('ratio',0,0);
 assert.equal(result,null);
 assert.match(ctx.error,/A base de janeiro é zero/)
});
