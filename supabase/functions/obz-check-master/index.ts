import { createClient } from "npm:@supabase/supabase-js@2.75.0";
const cors={"Access-Control-Allow-Origin":"https://lucianomaurina-art.github.io","Access-Control-Allow-Methods":"POST, OPTIONS","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Content-Type":"application/json"};
const reply=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers:cors});
function csvParse(t:string){
 let rows:string[][]=[],row:string[]=[],v="",q=false;
 for(let i=0;i<t.length;i++){const c=t[i];if(c==='"'){if(q&&t[i+1]==='"'){v+='"';i++}else q=!q;continue}
 if(c===","&&!q){row.push(v);v="";continue}
 if((c==="\n"||c==="\r")&&!q){if(c==="\r"&&t[i+1]==="\n")i++;row.push(v);rows.push(row);row=[];v="";continue}v+=c}
 if(v||row.length){row.push(v);rows.push(row)}return rows
}
function cents(v:unknown){let s=String(v??"").replace(/R\$/g,"").replace(/\s/g,"").trim();if(!s||s==="-")return 0;const neg=s[0]==="("||s[0]==="-";const n=Number(s.replace(/[()\-]/g,"").replace(/\./g,"").replace(",","."));if(!Number.isFinite(n))throw Error("Valor de moeda inválido");return Math.round(n*100)*(neg?-1:1)}
function normalized(s:string){return s.normalize("NFD").replace(/[\u0300-\u036f]/g,"").toUpperCase().replace(/[^A-Z0-9]+/g,"_").replace(/^_|_$/g,"")}
Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS")return new Response(null,{status:204,headers:cors});
 if(req.method!=="POST")return reply({error:"Método não permitido"},405);
 const url=Deno.env.get("SUPABASE_URL")||"";
 const key=Deno.env.get("SUPABASE_ANON_KEY")||JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS")||"{}").default;
 const auth=req.headers.get("authorization")||"";
 if(!url||!key||!auth)return reply({error:"Autenticação obrigatória"},401);
 const client=createClient(url,key,{global:{headers:{Authorization:auth}},auth:{autoRefreshToken:false,persistSession:false}});
 const {data:{user},error:authError}=await client.auth.getUser();
 if(authError||!user)return reply({error:"Sessão inválida"},401);
 const {data:profile}=await client.from("profiles").select("role,active").eq("id",user.id).maybeSingle();
 if(!profile?.active||profile.role!=="admin")return reply({error:"Acesso restrito à administração"},403);
 try{
  const source="https://docs.google.com/spreadsheets/d/1MiRtyjsR4plGiaone1x-89DcyMX8UzsDmVKptzKZ9E4/export?format=csv&gid=587542658";
  const res=await fetch(source,{signal:AbortSignal.timeout(18000)});
  if(!res.ok)throw Error("Google Sheets não permitiu leitura (HTTP "+res.status+")");
  const txt=await res.text();
  if(txt.length>6000000||/<html|<!doctype/i.test(txt.slice(0,700)))throw Error("A planilha não está disponível para leitura automática externa");
  const records=csvParse(txt);
  if(!records.some(x=>x[0]?.replace(/^\uFEFF/,"").trim()==="NATUREZA"&&x[1]?.trim()==="Centro de custo"&&x.length>=19))throw Error("CSV da planilha possui formato inesperado");
  const sourceMap=new Map<string,{category:string;description:string;account:string;months:number[]}>();
  records.forEach((x,i)=>{const category=x[2]?.trim();if(category!=="RECEITAS"&&category!=="DESPESAS")return;
    const name=(x[1]||"").trim();const key="OBZ2027:"+normalized(name)+":"+(i+1);
    sourceMap.set(key,{category:category==="RECEITAS"?"revenue":"expense",description:(x[5]||"").trim(),account:(x[4]||"").trim(),months:Array.from({length:12},(_,j)=>cents(x[6+j]))})});
  if(sourceMap.size<100)throw Error("Arquivo não contém as rubricas esperadas");
  const {data:lines,error:lineError}=await client.from("obz_lines").select("source_key,category,description,account_code,months");
  if(lineError)throw Error("Sem permissão para verificar as rubricas cadastradas");
  const imported=new Map((lines||[]).map(x=>[x.source_key,x]));
  let added=0,changed=0,removed=0,amountChanges=0;
  const samples:string[]=[];
  for(const [key,x] of sourceMap){const old=imported.get(key);
   if(!old){added++;if(samples.length<8)samples.push(key);continue}
   const numeric=x.months.some((n,j)=>n!==Math.round(Number(old.months?.[j]||0)*100));
   if(numeric||x.category!==old.category||x.description!==(old.description||"").trim()||x.account!==(old.account_code||"").trim()){
    changed++;if(numeric)amountChanges++;if(samples.length<8)samples.push(key)
   }}
  for(const key of imported.keys())if(!sourceMap.has(key)){removed++;if(samples.length<8)samples.push(key)}
  return reply({status:added+changed+removed?"divergent":"in_sync",checked_at:new Date().toISOString(),diff:{added,changed,removed,amount_changes:amountChanges,source_lines:sourceMap.size,imported_lines:imported.size,samples}});
 }catch(e){return reply({status:"unavailable",checked_at:new Date().toISOString(),message:String(e instanceof Error?e.message:e).slice(0,250)})}
});