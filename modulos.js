// Módulos conectados: todas as gravações passam pelo Supabase com RLS ou RPC.
let modules={orders:[],items:[],receivables:[],payments:[],accounts:[],entries:[],expenses:[],reps:[],campaigns:[],partners:[]};
let draftItems=[];
const todayBR=()=>new Intl.DateTimeFormat('en-CA',{timeZone:'America/Sao_Paulo',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
const dateBR=s=>s?`${s.slice(8,10)}/${s.slice(5,7)}/${s.slice(0,4)}`:'';
const byId=(list,id)=>list.find(x=>x.id===id);
const opts=(selector,rows,label,blank)=>{const el=$(selector),previous=el.value;el.replaceChildren();if(blank!==undefined){const o=document.createElement('option');o.value='';o.textContent=blank;el.append(o)}for(const r of rows){const o=document.createElement('option');o.value=r.id;o.textContent=label(r);el.append(o)}if(previous&&rows.some(r=>r.id===previous))el.value=previous};
const row=(values)=>{const tr=document.createElement('tr');for(const value of values){const td=document.createElement('td');td.textContent=String(value??'');tr.append(td)}return tr};
const listItem=(value)=>{const li=document.createElement('li');li.textContent=value;return li};
const inCompany=()=>`&company_id=eq.${state.companyId}`;

async function loadModules(){
  const [orders,items,receivables,payments,accounts,entries,expenses,reps,campaigns,partners]=await Promise.all([
    rest('orders',`?select=id,customer_name,placed_on,status,representative_id,campaign_id,customer_id${inCompany()}&order=created_at.desc`),
    rest('order_items',`?select=id,order_id,product_id,quantity,unit_price,minimum_expiry${inCompany()}`),
    rest('receivables',`?select=id,order_id,due_on,amount,payment_method,status${inCompany()}&order=due_on.asc`),
    rest('payments',`?select=id,receivable_id,amount,paid_on,reference${inCompany()}&order=paid_on.desc`),
    rest('bank_accounts',`?select=id,bank,nickname,agency,account_number${inCompany()}&order=created_at.desc`),
    rest('bank_entries',`?select=id,bank_account_id,booked_on,amount,description,payment_id,external_id${inCompany()}&order=booked_on.desc`),
    rest('expenses',`?select=id,incurred_on,category,description,amount${inCompany()}&order=incurred_on.desc`),
    rest('representatives',`?select=id,name,phone,commission_percent,active${inCompany()}&order=name`),
    rest('campaigns',`?select=id,name,starts_on,ends_on,target_amount${inCompany()}&order=starts_on.desc`),
    rest('partners',`?select=id,kind,name,document,phone,email,city,state_code${inCompany()}&order=name`)
  ]);
  modules={orders,items,receivables,payments,accounts,entries,expenses,reps,campaigns,partners};
  renderModules();
}
function orderAmount(o){return modules.items.filter(i=>i.order_id===o.id).reduce((sum,i)=>sum+Math.round(Number(i.quantity)*Number(i.unit_price)*100)/100,0)}
function renderModules(){
  const m=modules;
  opts('#sku-product',state.products,p=>`${p.name}${p.sku?' · '+p.sku:''}`,'Selecione um produto');
  opts('#sale-customer',m.partners.filter(p=>p.kind==='cliente'),p=>p.name,'Selecione um cliente');
  opts('#sale-representative',m.reps.filter(r=>r.active),r=>r.name,'Sem representante');
  opts('#sale-campaign',m.campaigns,r=>r.name,'Sem campanha');
  opts('#payment-receivable',m.receivables.filter(r=>r.status!=='pago'&&r.status!=='cancelado'),r=>`${byId(m.orders,r.order_id)?.customer_name||'Cliente'} — ${money(Number(r.amount)-paidAmount(r.id))} em aberto`,'Selecione uma cobrança');
  opts('#entry-account',m.accounts,r=>`${r.bank} — ${r.nickname}`,'Selecione uma conta');
  opts('#csv-account',m.accounts,r=>`${r.bank} — ${r.nickname}`,'Selecione uma conta');
  opts('#reconcile-entry',m.entries.filter(e=>!e.payment_id&&Number(e.amount)>0),e=>`${dateBR(e.booked_on)} · ${money(e.amount)} · ${e.description||''}`,'Selecione uma entrada');
  opts('#reconcile-payment',m.payments.filter(p=>!m.entries.some(e=>e.payment_id===p.id)),p=>`${money(p.amount)} · ${byId(m.orders,byId(m.receivables,p.receivable_id)?.order_id)?.customer_name||''}`,'Selecione um pagamento');
  $('#order-rows').replaceChildren(...m.orders.map(o=>{const items=m.items.filter(x=>x.order_id===o.id);return row([dateBR(o.placed_on),o.customer_name,items.map(i=>byId(state.products,i.product_id)?.name||'').join(', '),items.map(i=>i.quantity).join(' + '),money(orderAmount(o)),o.status])}));
  $('#receivable-rows').replaceChildren(...m.receivables.map(r=>row([byId(m.orders,r.order_id)?.customer_name||'',dateBR(r.due_on),money(r.amount),money(paidAmount(r.id)),r.status])));
  $('#expense-rows').replaceChildren(...m.expenses.map(e=>row([dateBR(e.incurred_on),e.category,e.description,money(e.amount)])));
  $('#account-rows').replaceChildren(...m.accounts.map(a=>listItem(`${a.bank} — ${a.nickname}${a.agency?' · ag. '+a.agency:''}`)));
  $('#entry-rows').replaceChildren(...m.entries.map(e=>row([dateBR(e.booked_on),byId(m.accounts,e.bank_account_id)?.nickname||'',e.description||'',money(e.amount),e.payment_id?'Conciliado':'Pendente'])));
  $('#rep-rows').replaceChildren(...m.reps.map(r=>listItem(`${r.name} · ${r.phone||'Sem telefone'} · comissão ${r.commission_percent}%`)));
  $('#campaign-rows').replaceChildren(...m.campaigns.map(c=>listItem(`${c.name} · ${dateBR(c.starts_on)} a ${dateBR(c.ends_on)} · meta ${money(c.target_amount)}`)));
  renderPartners();
  const revenue=m.orders.reduce((sum,o)=>sum+orderAmount(o),0);
  $('#report-summary').textContent=`${m.orders.length} pedido(s) · ${money(revenue)} em vendas registradas · ${money(m.receivables.reduce((sum,r)=>sum+Number(r.amount)-paidAmount(r.id),0))} a receber.`;
  $('#report-rows').replaceChildren(...m.orders.map(o=>row([dateBR(o.placed_on),o.customer_name,money(orderAmount(o)),byId(m.reps,o.representative_id)?.name||'',byId(m.campaigns,o.campaign_id)?.name||''])));
  renderBuy();
}
function paidAmount(receivableId){return modules.payments.filter(p=>p.receivable_id===receivableId).reduce((sum,p)=>sum+Number(p.amount),0)}
function saleLine(d){
  if(!d.product||!d.quantity||!d.unit_price||!d.min_expiry)return null;
  const quantity=Number(d.quantity),unit_price=Number(d.unit_price);
  if(!byId(state.products,d.product)||!Number.isFinite(quantity)||quantity<=0||!Number.isFinite(unit_price)||unit_price<=0||!/^\d{4}-\d{2}-\d{2}$/.test(d.min_expiry))throw Error('Confira produto, quantidade, preço e validade.');
  return {product_id:d.product,quantity,unit_price,min_expiry:d.min_expiry};
}
function renderDraft(){
  const el=$('#draft-preview');el.replaceChildren();
  if(!draftItems.length)return;
  const title=document.createElement('h3');title.textContent=`Produtos adicionados (${draftItems.length}) · ${money(draftItems.reduce((sum,i)=>sum+Math.round(i.quantity*i.unit_price*100)/100,0))}`;el.append(title);
  for(const [n,i] of draftItems.entries()){
    const p=document.createElement('p'),b=document.createElement('button');b.type='button';b.className='secondary';b.textContent='Remover';b.addEventListener('click',()=>{draftItems.splice(n,1);renderDraft()});
    p.append(document.createTextNode(`${byId(state.products,i.product_id)?.name||'Produto'} · ${i.quantity} × ${money(i.unit_price)} · validade mínima ${dateBR(i.min_expiry)} `),b);el.append(p)
  }
}
function renderPartners(){const kind=$('#partner-kind').value;$('#partner-rows').replaceChildren(...modules.partners.filter(p=>p.kind===kind).map(p=>row([p.name,p.document||'',p.phone||p.email||'',`${p.city||''} ${p.state_code||''}`])))}
function selectPartnerKind(kind){if(!kind)return;$('#partner-kind').value=kind;$('#partner-title').textContent={cliente:'Clientes',fornecedor:'Fornecedores',transportadora:'Transportadoras'}[kind];renderPartners()}
function renderBuy(){
  if(!$('#buy-rows'))return;
  const days=Math.max(1,Math.min(180,Number($('#target-days').value)||30));
  const start=new Date(`${todayBR()}T12:00:00Z`);start.setUTCDate(start.getUTCDate()-29);
  const cutoff=start.toISOString().slice(0,10),today=todayBR();
  const data=state.products.map(p=>{
    const recent=modules.orders.filter(o=>o.status==='aprovado'&&o.placed_on>=cutoff);
    const items=recent.flatMap(o=>modules.items.filter(i=>i.order_id===o.id&&i.product_id===p.id));
    const sold=items.reduce((sum,i)=>sum+Number(i.quantity),0);
    const revenue=items.reduce((sum,i)=>sum+Math.round(Number(i.quantity)*Number(i.unit_price)*100)/100,0);
    const stock=(state.lots||[]).filter(l=>l.product_id===p.id&&l.expires_on>=today).reduce((sum,l)=>sum+Number(l.quantity),0);
    const buy=Math.max(0,Math.ceil(sold/30*days-stock));
    return {p,sold,revenue,stock,buy};
  }).sort((a,b)=>b.revenue-a.revenue);
  $('#buy-rows').replaceChildren(...data.map(x=>row([`${x.p.sku||'Sem SKU'} · ${x.p.name}`,money(x.revenue),`${x.sold} ${x.p.base_unit}`,`${x.stock} ${x.p.base_unit}`,`${x.buy} ${x.p.base_unit}`])));
}
async function refreshModules(){await loadStock();await loadModules()}
function bindForm(selector,action,success){$(selector).addEventListener('submit',async e=>{
  e.preventDefault();const form=e.currentTarget,button=e.submitter||form.querySelector('button'),data=Object.fromEntries(new FormData(form));
  button.disabled=true;
  try{await action(data,form);await refreshModules();form.reset();delete form.dataset.requestKey;if(form.id==='sale-form'){draftItems=[];renderDraft()}setDateDefaults();selectPartnerKind($('#tabs button[aria-selected=true]')?.dataset.kind);status(success)}catch(err){status(err.message,true)}finally{button.disabled=false}
})}
function setDateDefaults(){for(const input of document.querySelectorAll('input[type=date][name="paid_on"],input[type=date][name="incurred_on"],input[type=date][name="booked_on"]'))if(!input.value)input.value=todayBR()}
function csvCell(value){let s=String(value??'');if(/^[\s]*[=+@-]/.test(s))s="'"+s;return '"'+s.replaceAll('"','""')+'"'}
function csvRows(source){
  const rows=[],current=[];let field='',quoted=false;
  for(let n=0;n<source.length;n++){
    const c=source[n];
    if(c==='"'){if(quoted&&source[n+1]==='"'){field+='"';n++}else quoted=!quoted}
    else if(c===';'&&!quoted){current.push(field);field=''}
    else if((c==='\n'||c==='\r')&&!quoted){if(c==='\r'&&source[n+1]==='\n')n++;current.push(field);field='';if(current.some(x=>x.trim()))rows.push([...current]);current.length=0}
    else field+=c;
  }
  if(quoted)throw Error('CSV com aspas incompletas.');
  current.push(field);if(current.some(x=>x.trim()))rows.push(current);
  return rows;
}
function isoDate(s){const raw=s.trim(),m=raw.match(/^(\d{2})\/(\d{2})\/(\d{4})$/);const iso=m?`${m[3]}-${m[2]}-${m[1]}`:raw;const parsed=new Date(`${iso}T00:00:00Z`);if(!/^\d{4}-\d{2}-\d{2}$/.test(iso)||!Number.isFinite(parsed.getTime())||parsed.toISOString().slice(0,10)!==iso)throw Error(`Data inválida no CSV: ${raw}`);return iso}

$('#tabs').addEventListener('click',e=>{const button=e.target.closest('button[data-tab]');if(!button)return;for(const b of $('#tabs').querySelectorAll('button'))b.setAttribute('aria-selected',String(b===button));for(const section of document.querySelectorAll('.module'))section.hidden=section.id!==`tab-${button.dataset.tab}`;selectPartnerKind(button.dataset.kind)});
$('#target-days').addEventListener('input',renderBuy);
$('#add-sale-line').addEventListener('click',()=>{const form=$('#sale-form'),d=Object.fromEntries(new FormData(form));try{const line=saleLine(d);if(!line)throw Error('Preencha produto, quantidade, preço e validade antes de adicionar.');draftItems.push(line);form.elements.quantity.value='';form.elements.unit_price.value='';form.elements.min_expiry.value='';renderDraft();status('Produto adicionado ao pedido.')}catch(err){status(err.message,true)}});
bindForm('#sku-form',async d=>{await rest('products',`?id=eq.${encodeURIComponent(d.product_id)}&company_id=eq.${state.companyId}`,{method:'PATCH',body:{sku:d.sku.trim()},prefer:'return=minimal'})},'SKU atualizado.');

bindForm('#partner-form',async d=>{if(d.state_code&& !/^[a-zA-Z]{2}$/.test(d.state_code))throw Error('Informe a UF com duas letras.');await rest('partners','',{method:'POST',body:{company_id:state.companyId,kind:d.kind,name:d.name.trim(),document:d.document.trim()||null,phone:d.phone.trim()||null,email:d.email.trim()||null,city:d.city.trim()||null,state_code:d.state_code.trim().toUpperCase()||null},prefer:'return=minimal'})},'Cadastro salvo no banco.');
bindForm('#rep-form',async d=>{await rest('representatives','',{method:'POST',body:{company_id:state.companyId,name:d.name.trim(),phone:d.phone.trim()||null,commission_percent:Number(d.commission_percent)},prefer:'return=minimal'})},'Representante salvo.');
bindForm('#campaign-form',async d=>{if(d.ends_on<d.starts_on)throw Error('O fim deve ser depois do início.');await rest('campaigns','',{method:'POST',body:{company_id:state.companyId,name:d.name.trim(),starts_on:d.starts_on,ends_on:d.ends_on,target_amount:Number(d.target_amount)},prefer:'return=minimal'})},'Campanha salva.');
bindForm('#sale-form',async (d,form)=>{
  const customer=byId(modules.partners,d.customer_id);
  if(!customer||customer.kind!=='cliente')throw Error('Cadastre um cliente antes de registrar o pedido.');
  const anyCurrent=[d.quantity,d.unit_price,d.min_expiry].some(Boolean),current=saleLine(d);
  if(anyCurrent&&!current)throw Error('Complete os dados do produto atual ou adicione os produtos já listados.');
  const items=[...draftItems,...(current?[current]:[])];
  if(!items.length)throw Error('Adicione pelo menos um produto ao pedido.');
  form.dataset.requestKey ||= crypto.randomUUID();
  await rest('rpc/register_order','',{method:'POST',body:{p_company:state.companyId,p_customer_id:customer.id,p_items:items,p_due:d.due,p_payment_method:d.payment_method,p_freight_terms:d.freight_terms,p_representative:d.representative||null,p_campaign:d.campaign||null,p_request:form.dataset.requestKey}});
},'Venda registrada, estoque baixado e cobrança pendente criada.');
bindForm('#payment-form',async (d,form)=>{form.dataset.requestKey ||= crypto.randomUUID();await rest('rpc/record_payment','',{method:'POST',body:{p_company:state.companyId,p_receivable:d.receivable,p_amount:Number(d.amount),p_paid_on:d.paid_on,p_reference:d.reference||null,p_request:form.dataset.requestKey}})},'Pagamento registrado sem exigir conciliação.');
bindForm('#expense-form',async d=>{await rest('expenses','',{method:'POST',body:{company_id:state.companyId,user_id:state.session.user.id,incurred_on:d.incurred_on,category:d.category.trim(),description:d.description.trim(),amount:Number(d.amount)},prefer:'return=minimal'})},'Despesa salva.');
bindForm('#account-form',async d=>{await rest('bank_accounts','',{method:'POST',body:{company_id:state.companyId,bank:d.bank,nickname:d.nickname.trim(),agency:d.agency||null,account_number:d.account_number||null},prefer:'return=minimal'})},'Conta bancária cadastrada.');
bindForm('#entry-form',async d=>{if(!Number(d.amount))throw Error('O valor deve ser diferente de zero.');await rest('bank_entries','',{method:'POST',body:{company_id:state.companyId,bank_account_id:d.account,booked_on:d.booked_on,amount:Number(d.amount),description:d.description||null},prefer:'return=minimal'})},'Lançamento bancário salvo.');
bindForm('#csv-form',async (d,form)=>{
  if(!byId(modules.accounts,d.account))throw Error('Selecione uma conta bancária.');
  const buffer=await d.file.arrayBuffer();let source;
  try{source=new TextDecoder('utf-8',{fatal:true}).decode(buffer)}catch{source=new TextDecoder('windows-1252').decode(buffer)}
  const rows=csvRows(source.replace(/^\ufeff/,''));if(rows.length<2||rows.length>1001)throw Error('O CSV precisa ter cabeçalho e até 1.000 lançamentos.');
  const labels=rows.shift().map(x=>x.trim().normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase());
  const cols=Object.fromEntries(['data','valor','descricao','id'].map(k=>[k,labels.indexOf(k)]));
  if(cols.data<0||cols.valor<0||cols.descricao<0)throw Error('Cabeçalho esperado: data;valor;descricao;id (id opcional).');
  const digest=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',buffer))).map(b=>b.toString(16).padStart(2,'0')).join('');
  const known=new Set(modules.entries.filter(e=>e.bank_account_id===d.account).map(e=>e.external_id));
  const incoming=new Set(),payload=[];
  rows.forEach((cells,n)=>{
    const raw=(cells[cols.valor]||'').trim();const normalized=raw.includes(',')?raw.replace(/\./g,'').replace(',','.'):raw;
    const amount=Number(normalized);if(!Number.isFinite(amount)||!amount||Math.abs(Math.round(amount*100)-amount*100)>0.00001)throw Error(`Valor inválido na linha ${n+2}.`);
    const id=cols.id>=0?cells[cols.id]?.trim():'';
    const external_id=id?`csv:${id}`:`csv:${digest}:${n+2}`;
    if(incoming.has(external_id))throw Error(`ID duplicado no arquivo, linha ${n+2}.`);
    incoming.add(external_id);
    if(!known.has(external_id))payload.push({company_id:state.companyId,bank_account_id:d.account,booked_on:isoDate(cells[cols.data]||''),amount,description:(cells[cols.descricao]||'').trim(),external_id});
  });
  if(!payload.length)throw Error('Todos os lançamentos desse arquivo já foram importados.');
  await rest('bank_entries','',{method:'POST',body:payload,prefer:'return=minimal'});
},'Extrato CSV importado. Concilie apenas as entradas que correspondem a pagamentos.');
bindForm('#reconcile-form',async d=>{await rest('rpc/reconcile_entry','',{method:'POST',body:{p_company:state.companyId,p_entry:d.entry,p_payment:d.payment}})},'Pagamento e entrada conciliados.');
$('#export-report').addEventListener('click',()=>{
  const records=[['Data','Cliente','Produto','Quantidade','Valor','Representante','Campanha'],...modules.orders.map(o=>{const items=modules.items.filter(i=>i.order_id===o.id);return [dateBR(o.placed_on),o.customer_name,items.map(i=>byId(state.products,i.product_id)?.name||'').join(', '),items.map(i=>i.quantity).join(' + '),orderAmount(o).toFixed(2),byId(modules.reps,o.representative_id)?.name||'',byId(modules.campaigns,o.campaign_id)?.name||'']})];
  const blob=new Blob(['\ufeff'+records.map(r=>r.map(csvCell).join(';')).join('\r\n')],{type:'text/csv;charset=utf-8'});
  const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='terra-nova-vendas.csv';a.click();setTimeout(()=>URL.revokeObjectURL(url),5000)
});
setDateDefaults();
