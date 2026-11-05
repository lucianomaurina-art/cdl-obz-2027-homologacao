/* OBZ 2027: importador local de CSV exportado da Planilha Mestra.
 * Não envia o arquivo para servidores; somente a importação confirmada usa Supabase.
 * Layout A:S: A tipo, B centro, C grupo, D conta, E código, F descrição, G:R meses, S total.
 */
(function(){
'use strict';
const file=document.getElementById('csvFile'),report=document.getElementById('csvReport'),json=document.getElementById('json');
if(!file||!report||!json)return;
function parseCSV(text,delimiter){
 const rows=[];let row=[],cell='',quoted=false;
 text=text.replace(/^\uFEFF/,'');
 for(let i=0;i<text.length;i++){const c=text[i];
 if(quoted){if(c==='"'&&text[i+1]==='"'){cell+='"';i++}else if(c==='"')quoted=false;else cell+=c}
 else if(c==='"')quoted=true;
 else if(c===delimiter){row.push(cell);cell=''}
 else if(c==='\n'||c==='\r'){if(c==='\r'&&text[i+1]==='\n')i++;row.push(cell);if(row.some(x=>x.trim()))rows.push(row);row=[];cell=''}
 else cell+=c;
 }
 if(quoted)throw Error('CSV com aspas não fechadas');
 row.push(cell);if(row.some(x=>x.trim()))rows.push(row);
 return rows;
}
function numeric(raw){let s=String(raw??'').trim();if(!s||s==='-')return 0;
 const neg=/^\(.*\)$/.test(s);s=s.replace(/[R$\s()\u00a0]/g,'');
 if(!/^-?[\d.,]+$/.test(s))throw Error('Número inválido: '+raw);
 const comma=s.lastIndexOf(','),dot=s.lastIndexOf('.');
 if(comma>=0&&dot>=0)s=comma>dot?s.replace(/\./g,'').replace(',','.'):s.replace(/,/g,'');
 else if(comma>=0)s=s.replace(/\./g,'').replace(',','.');
 else if(dot>=0&&/\.\d{3}(?:\.\d{3})*$/.test(s))s=s.replace(/\./g,'');
 const n=Number(s)*(neg?-1:1);if(!Number.isFinite(n))throw Error('Valor inválido');return Math.round(n*100)/100;
}
function make(text){
 const lines=text.split(/\r?\n/).filter(x=>x.trim()),semi=(lines[0]?.match(/;/g)||[]).length,comma=(lines[0]?.match(/,/g)||[]).length;
 // A full Google Sheet CSV has at least 19 columns; choose separator from first row.
 const delim=semi>comma?';':',';
 const rows=parseCSV(text.replaceAll('\u0000',''),delim); // parser uses detected delimiter
 // The CSV must represent the complete Orçamento 2027 sheet, including control totals.
 const result=[],warnings=[],totals={revenue:0,expense:0},control={revenue:null,expense:null,result:null};let seen=new Set();
 rows.forEach((r,i)=>{if(r.length<19)return;
 const center=String(r[1]||'').trim().toUpperCase(),group=String(r[2]||'').trim().toUpperCase(),description=String(r[5]||'').trim();
 if(center!=='SPC BRASIL'||!description)return;
 if(group==='TOTAL RECEITAS'||group==='TOTAL DESPESAS'||group==='RESULTADO DO CENTRO'){const k=group==='TOTAL RECEITAS'?'revenue':group==='TOTAL DESPESAS'?'expense':'result';try{control[k]=numeric(r[18])}catch(e){warnings.push('Linha '+(i+1)+': subtotal inválido')}return;}if(group==='CENTRO DE CUSTO')return;
 const category=group==='RECEITAS'?'revenue':group==='DESPESAS'?'expense':null;
 if(!category){warnings.push('Linha '+(i+1)+': grupo não reconhecido ('+group+')');return}
 let months;try{months=r.slice(6,18).map(numeric)}catch(e){warnings.push('Linha '+(i+1)+': '+e.message);return}
 const sourceKey='OBZ2027:SPC:'+String(i+1); // row index stable only for complete-sheet export
 if(seen.has(sourceKey))throw Error('Identificador duplicado');seen.add(sourceKey);
 const item={source_key:sourceKey,category,description,account_code:String(r[4]||''),months};
 const total=months.reduce((a,b)=>a+b,0);totals[category]+=total;
 if(r[18]&&r[18].trim()!=='-'){const annual=numeric(r[18]);if(Math.abs(annual-total)>0.06)warnings.push('Linha '+(i+1)+': total anual divergente em '+(annual-total).toFixed(2))}
 result.push(item);
 });
 if(!result.length)throw Error('Nenhuma rubrica SPC Brasil reconhecida. Exporte A:S da aba Orçamento 2027.');
 if(control.revenue===null||control.expense===null||control.result===null)throw Error('CSV sem as três linhas de controle (total receitas, total despesas, resultado). Exporte a aba inteira, não um recorte.');
 const cents=n=>Math.round(n*100);const actual={revenue:totals.revenue,expense:totals.expense,result:totals.revenue-totals.expense};
 for(const k of Object.keys(control)){if(Math.abs(cents(actual[k])-cents(control[k]))>2)throw Error('Conciliação bloqueada em '+k+': rubricas '+actual[k].toFixed(2)+' versus subtotal '+control[k].toFixed(2));}
 if(warnings.length)throw Error('Importação bloqueada por '+warnings.length+' divergência(s): '+warnings.slice(0,5).join(' | '));
 return {result,warnings,totals,delim};
}
file.addEventListener('change',async()=>{report.textContent='';if(!file.files?.length)return;
 try{const {result,warnings,totals}=make(await file.files[0].text());
 json.value=JSON.stringify(result,null,2);json.dispatchEvent(new Event('input'));
 report.textContent=result.length+' rubricas identificadas. Receitas: R$ '+totals.revenue.toFixed(2)+'; despesas: R$ '+totals.expense.toFixed(2)+'. '+(warnings.length?'ATENÇÃO: '+warnings.slice(0,12).join(' | '):'Sem divergências de total detectadas.')+' Clique em “Validar prévia” e confira os totais com a planilha.';
 }catch(e){json.value='';json.dispatchEvent(new Event('input'));report.textContent='Erro: '+e.message}
});
})();
