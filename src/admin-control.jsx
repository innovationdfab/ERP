import {matchesSearch} from './filter-rules.js';
import React, {useCallback,useEffect,useMemo,useState} from 'react';
import {ArrowLeft,ArrowRight,Check,CheckCircle2,AlertCircle,ChevronDown,ClipboardList,Database,FileCheck2,GitBranch,LayoutDashboard,Layers3,LoaderCircle,Plus,RefreshCw,Save,Search,ShieldCheck,Trash2,UserPlus,Users,X} from 'lucide-react';
import {askConfirmation} from './in-app-dialog.jsx';
import {temporaryPasswordIssue} from './employee-password-policy.js';
import {loadAdminDashboard,saveDepartment,saveRole,saveUser,inviteUser,resetEmployeeLogin,revokeEmployeeLogin,restoreEmployeeLogin,saveTemplate,publishTemplate,unpublishTemplate,registerStorage,deleteDraftTemplate,deleteDepartment,deleteRole,unmapStorage} from './admin-api.js';
import {ACTIONS,normalizedEdges,validateTemplateEdges} from './admin-permissions.js';
import {traceDocument} from './admin-lineage.js';
import {generateRegisteredFlows} from './admin-workflow-generator.js';
import {imantraReportDefinitions} from './imantra-integration.js';
import './admin-control.css';

const blankDepartment={code:'',name:'',cost_center:'',active:true};
const blankRole={code:'',name:'',description:'',active:true,rights:[]};
const blankInvitation={email:'',role_ids:[]};
const blankPasswordFields={password:'',confirm:''};
const trim=s=>String(s??'').trim();
const dateTime=s=>s?new Date(s).toLocaleString('en-IN',{dateStyle:'medium',timeStyle:'short'}):'—';
const makeRights=(rights=[])=>rights.map(r=>({page:r.page,...Object.fromEntries(ACTIONS.map(a=>[a,Boolean(r[`can_${a}`]??r[a])]))}));
const listForTemplate=(template,data)=>data.edges.filter(e=>e.template_id===template.id).map(e=>({source_page:e.source_page,target_page:e.target_page,gate_statuses:e.gate_statuses||[],field_map:e.field_map||{}}));
const presetEdges=catalog=>catalog.filter(c=>c.default_next&&catalog.some(t=>t.page===c.default_next)&&c.fields.length).map(c=>({source_page:c.page,target_page:c.default_next,gate_statuses:[],field_map:{}}));
const toRightsItem=(page,r={})=>({page,...Object.fromEntries(ACTIONS.map(a=>[a,Boolean(r[a])]))});
// Only Admin navigation is reconstructed; the ERP's outer navigation remains locked.
const ADMIN_DASHBOARD=['overview','Dashboard',LayoutDashboard];
const ADMIN_NAV_GROUPS=[
 {id:'team',label:'Team & Access',icon:Users,items:[['users','Logins',Users],['departments','Departments',Layers3],['roles','Roles & permissions',ShieldCheck]]},
 {id:'documents',label:'Document Connections',icon:GitBranch,items:[['workflows','Document flows',GitBranch],['lineage','Data connections',Database]]},
 {id:'oversight',label:'Oversight',icon:ClipboardList,items:[['audit','Activity history',ClipboardList],['storage','Advanced settings',Database]]},
];
const groupForTab=id=>ADMIN_NAV_GROUPS.find(group=>group.items.some(([key])=>key===id))?.id||'team';
const ADMIN_SECTION_HELP={
 users:{title:'Manage ERP logins',detail:'Create an account using an email, an ERP role and a password. Supabase Auth stores the password securely and the ERP stores access permissions.',result:'Only accounts with enabled access can enter ERP. This is an account directory, not live online-presence tracking.'},
 departments:{title:'Department details used across the company',detail:'Create or edit departments here, then assign employees to them in Employees.',result:'Saved department changes are available to other modules that read this shared company setup.'},
 roles:{title:'What each employee is allowed to do',detail:'Assign View, Create, Edit, Delete, Approve and Export rights by ERP module and role.',result:'Permissions are checked by the existing ERP access layer; employees may need to refresh to get new access.'},
 workflows:{title:'How one document creates the next',detail:'Review the current connections, edit a draft template and publish only after approval.',result:'Publishing updates future document handoffs; it does not rewrite existing records.'},
 lineage:{title:'Follow information from entry to report',detail:'Select an ERP document to inspect its saved section, linked documents, mapped fields and registered reports.',result:'This is a read-only explanation. Viewing connections never modifies company data.'},
 audit:{title:'Track administrator changes',detail:'Review recorded changes to employees, roles, departments and workflow templates.',result:'The history is read-only in this screen.'},
 storage:{title:'Advanced storage ownership',detail:'Manage which ERP module owns an existing saved-data section. This can affect other departments.',result:'Changes are saved with server-side safeguards and should be reviewed before use.'},
};

function Empty({children}) {return <div className="admin-empty">{children}</div>}
function Button({children,busy=false,secondary=false,...props}) {return <button type="button" className={`admin-button ${secondary?'secondary':''}`} disabled={busy||props.disabled} {...props}>{busy?<LoaderCircle size={15} className="admin-spin"/>:null}{children}</button>}
function Status({type='success',children}) {return <p role={type==='error'?'alert':'status'} className={`admin-feedback ${type}`}>{children}</p>}
function Select({children,...props}){return <select {...props}>{children}</select>}
function Card({title,description,children,editor=false,onClose,busy=false,feedback=''}){return <section className={`admin-card ${editor?'admin-edit-card':''}`}><header className="admin-card-heading"><div><h2>{title}</h2>{description&&<p>{description}</p>}</div>{editor&&onClose&&<button type="button" className="admin-editor-back" disabled={busy} onClick={onClose}><ArrowLeft size={16} aria-hidden="true"/> Back to list</button>}</header>{editor&&feedback&&<Status type="error">{feedback}</Status>}{children}</section>}

export default function AdminControl({initialTab='overview',onWorkflowPublished=()=>{},storageKeys=[],storageCounts={}}) {
 const [data,setData]=useState(null),[loading,setLoading]=useState(true),[saving,setSaving]=useState(false);
 const [error,setError]=useState(''),[message,setMessage]=useState('');
 const [tab,setTab]=useState(initialTab);
 const [dashboardTab,dashboardLabel]=ADMIN_DASHBOARD;
 const [expandedGroups,setExpandedGroups]=useState(()=>({team:true,documents:groupForTab(initialTab)==='documents',oversight:groupForTab(initialTab)==='oversight'}));
 const [filter,setFilter]=useState('');
 const [template,setTemplate]=useState(null),[selectedTemplate,setSelectedTemplate]=useState('');
 const [department,setDepartment]=useState(null),[role,setRole]=useState(null),[user,setUser]=useState(null);
 const [inviting,setInviting]=useState(false),[invitation,setInvitation]=useState(blankInvitation);
 const [employeePassword,setEmployeePassword]=useState(blankPasswordFields);
 const [showEmployeePassword,setShowEmployeePassword]=useState(false);
 const [adminNotice,setAdminNotice]=useState(null);
 const [mapping,setMapping]=useState({storage_key:'',page_name:'',record_key_index:0,status_index:-1});
 const [roleGroup,setRoleGroup]=useState('All');
 const [newMap,setNewMap]=useState({from:'',to:''});
 const [showInactive,setShowInactive]=useState(true);
 const [showAllConnections,setShowAllConnections]=useState(false);
 const [inspectedPage,setInspectedPage]=useState('');
 const editorOpen=Boolean(department||role||user||inviting);
 const navigateTab=(next)=>{
  setTab(next);setExpandedGroups(groups=>({...groups,[groupForTab(next)]:true}));
  setDepartment(null);setRole(null);setUser(null);setInviting(false);
  setEmployeePassword({...blankPasswordFields});setShowEmployeePassword(false);
  setError('');setMessage('');setFilter('');setRoleGroup('All');setShowAllConnections(false);
 };
 useEffect(()=>{if(error)setAdminNotice({id:Date.now(),kind:'error',text:error});},[error]);
 useEffect(()=>{if(!adminNotice||adminNotice.kind==='error')return;const timeout=window.setTimeout(()=>setAdminNotice(null),4000);return()=>window.clearTimeout(timeout);},[adminNotice]);
 useEffect(()=>{setEmployeePassword({...blankPasswordFields});setShowEmployeePassword(false);},[tab]);
 useEffect(()=>{if(!editorOpen)return;const frame=window.requestAnimationFrame(()=>document.querySelector('.admin-simple .admin-edit-card')?.scrollIntoView({block:'start',behavior:'smooth'}));return ()=>window.cancelAnimationFrame(frame);},[editorOpen,tab,department?.id,role?.id,user?.user_id,inviting]);
 const load=useCallback(async()=>{setLoading(true);setError('');try{const response=await loadAdminDashboard();if(!response||!Array.isArray(response.departments))throw new Error('Admin database returned an invalid response. Apply ERP_ADMIN_CONTROL.sql.');setData(response);return true;}catch(e){setError(e.message||'Could not read administrator data from Supabase.');return false;}finally{setLoading(false)}},[]);
 useEffect(()=>{load()},[load]);
 const run=async(fn,success,notifyLocally=false)=>{setSaving(true);setError('');setMessage('');let confirmed=false;try{await fn();confirmed=true;const refreshed=await load();if(!refreshed){setError('Database confirmed the change, but the refreshed data could not be loaded. Refresh the panel and verify before retrying.');return false;}const successText=success||'Saved and verified in Supabase.';setMessage(successText);if(notifyLocally)setAdminNotice({id:Date.now(),kind:'success',text:successText});return true}catch(e){setError(confirmed?'Database saved the change, but a subsequent action failed. Refresh before retrying: '+(e.message||'unknown error'):(e.message||'Database save failed.'));return false}finally{setSaving(false)}};
 const groups=useMemo(()=>['All',...new Set((data?.catalog||[]).map(c=>c.module_group))],[data]);
 const workflowPages=useMemo(()=>(data?.catalog||[]).filter(c=>Array.isArray(c.fields)&&c.fields.length>0),[data]);
 const generated=useMemo(()=>generateRegisteredFlows(data?.catalog||[]),[data?.catalog]);
 const activeTemplate=data?.templates?.find(t=>t.status==='published');
 const knownConnections=activeTemplate?listForTemplate(activeTemplate,data||{edges:[]}):presetEdges(data?.catalog||[]);
 const connectedCount=knownConnections.length;
 const inspected=traceDocument({page:inspectedPage||knownConnections[0]?.source_page||workflowPages[0]?.page,catalog:data?.catalog||[],edges:knownConnections,storage:data?.storage||[],counts:storageCounts,reports:imantraReportDefinitions});
 const inboundConnections=inspected?(knownConnections||[]).filter(e=>e.target_page===inspected.page):[];
 const visibleConnections=knownConnections.filter(e=>(roleGroup==='All'||(data?.catalog||[]).some(c=>c.page===e.source_page&&c.module_group===roleGroup))&&matchesSearch([e.source_page,e.target_page,e.gate_statuses],filter));
 const filteredCatalog=(data?.catalog||[]).filter(c=>(roleGroup==='All'||c.module_group===roleGroup)&&matchesSearch([c.page,c.module_group],filter));
 const activeLoginRole=(data?.roles||[]).find(r=>r.id===(inviting?invitation.role_ids[0]:user?.role_ids?.[0]));
 const loginRoleRights=(data?.rights||[]).filter(entry=>entry.role_id===activeLoginRole?.id);
 const selectedRoleAccess=activeLoginRole?.code==='ADMIN'?'Administrator · all ERP modules':`${loginRoleRights.filter(entry=>entry.can_view).length} accessible modules · ${loginRoleRights.filter(entry=>entry.can_create).length} create · ${loginRoleRights.filter(entry=>entry.can_edit).length} edit · ${loginRoleRights.filter(entry=>entry.can_approve).length} approve`;
 const beginNewTemplate=()=>{setSelectedTemplate('');setTemplate({id:null,version:null,name:'',description:'',edges:normalizedEdges(knownConnections)});setNewMap({from:'',to:''});};
 const buildAutomaticTemplate=async()=>{
  if(generated.error||generated.skipped.length||generated.edges.length!==generated.totalDefined){
   setError(generated.error||`Some registered processes could not be mapped (${generated.skipped.length} skipped). Review the Admin catalog before generating.`);
   return;
  }
  if(!generated.edges.length){setError('No eligible registered ERP process connections are available.');return;}
  if(template&&!await askConfirmation('Replace the draft currently open with a newly generated complete workflow? Unsaved changes will be lost.'))return;
  if(activeTemplate&&!await askConfirmation('Generate a draft from the registered standard flows? Your active published workflow will stay unchanged until you explicitly publish the new draft.'))return;
  setSelectedTemplate('');setTemplate({id:null,version:null,
   name:'DFAB Standard Connected Workflow',
   description:'Built from registered DFAB ERP document paths, verified status gates and compatible source fields.',
   edges:normalizedEdges(generated.edges)});
  setNewMap({from:'',to:''});navigateTab('workflows');setError('');setMessage(`Prepared ${generated.edges.length} linked documents and ${generated.matchedFields} safe auto-fill mappings. Review and Save draft before publishing.`);
  setShowAllConnections(false);
 };
 const editTemplate=t=>{if(t.status==='published'){setError('Published workflow templates are locked. Create a new draft to modify the active flow.');return}setError('');setSelectedTemplate(t.id);setTemplate({id:t.id,version:t.version,name:t.name,description:t.description,edges:listForTemplate(t,data)});setNewMap({from:'',to:''});};
 const saveCurrentTemplate=async()=>{if(!template)return;
 const catalog=(data?.catalog||[]).map(c=>({name:c.page,columns:c.columns,fields:c.fields}));
 const validation=validateTemplateEdges(template.edges,catalog);if(validation){setError(validation);return}
 if(!trim(template.name)){setError('Enter a workflow template name.');return}
 const saved=await run(()=>saveTemplate({...template,edges:normalizedEdges(template.edges)}),'Workflow template saved as a draft. Published flow unchanged.');
 if(saved){setTemplate(null);setSelectedTemplate('');}
 };
 const publish=async t=>{if(!await askConfirmation(`Publish "${t.name}"? This changes which connected step appears in ERP transactions for all departments. Existing records are not rewritten.`))return;
 const ok=await run(()=>publishTemplate(t),'Workflow published. Employees will use the new connections after refreshing their session.');
 if(ok) await onWorkflowPublished();};
 const removeTemplate=async t=>{if(t.status!=='draft'){setError('Only draft templates can be deleted. Restore built-in workflow before removing a published template.');return;}if(!await askConfirmation(`Delete draft workflow template \"${t.name}\"? This cannot be undone.`))return;const ok=await run(()=>deleteDraftTemplate(t),'Draft workflow deleted and verified.');if(ok&&selectedTemplate===t.id){setTemplate(null);setSelectedTemplate('');}};
 const removeDepartment=async d=>{if(!await askConfirmation(`Permanently delete department \"${d.name}\"? Assigned employees or dependent business records will block deletion. You can disable it instead.`))return;const ok=await run(()=>deleteDepartment(d.id),'Unused department deleted.');if(ok&&department?.id===d.id)setDepartment(null);};
 const removeRole=async r=>{if(r.system_role||r.code==='ADMIN'){setError('Protected roles cannot be deleted.');return}if(!await askConfirmation(`Delete role \"${r.name}\"? Only roles with no employee assignments may be deleted.`))return;const ok=await run(()=>deleteRole(r.id),'Unused access role deleted.');if(ok&&role?.id===r.id)setRole(null);};
 const disableEmployee=async p=>{if(!await askConfirmation(`Disable ERP access for ${p.display_name||p.email}? Their records and audit trail will be retained. This does not delete their Supabase Auth identity.`))return;const ok=await run(()=>saveUser({...p,active:false,role_ids:[]}), 'Employee access disabled; historical records retained.');if(ok&&user?.user_id===p.user_id)setUser(null);};
 const deleteLogin=async p=>{
  if(!await askConfirmation(`Delete login access for ${p.email}? Sign-in will be blocked. Existing ERP business records and audit history will be retained.`))return;
  const ok=await run(()=>revokeEmployeeLogin(p.user_id),'Login access revoked. ERP history retained.',true);
  if(ok&&user?.user_id===p.user_id)setUser(null);
 };
 const removeStorageMap=async map=>{if(!await askConfirmation(`Remove the access mapping for ${map.storage_key}? Database records in that section will block this operation.`))return;await run(()=>unmapStorage(map.storage_key),'Unused storage access mapping removed.');};
 const reset=async()=>{if(!await askConfirmation('Return to the built-in ERP workflow connections? Saved templates will remain available as drafts.'))return;
 const ok=await run(()=>unpublishTemplate(),'Built-in workflow connections restored.');if(ok)await onWorkflowPublished();};
 const saveDepartmentForm=async()=>{if(!department)return; if(!/^[A-Z0-9_-]{2,24}$/.test(trim(department.code).toUpperCase())||trim(department.name).length<2){setError('Enter a 2–24 character department code and department name.');return}
 const ok=await run(()=>saveDepartment(department),'Department saved to Supabase.');if(ok)setDepartment(null);};
 const selectRole=r=>{if(r.system_role){setError('The built-in Administrator role is protected. Create a departmental role instead.');return}
 setError('');setRole({...r,rights:makeRights((data.rights||[]).filter(a=>a.role_id===r.id))});};
 const setRolePermission=(page,action,checked)=>setRole(prev=>{const rights=[...prev.rights],idx=rights.findIndex(r=>r.page===page);const next=idx<0?toRightsItem(page):{...rights[idx]};next[action]=checked;
 if(action!=='view'&&checked)next.view=true;
 if(idx<0)rights.push(next);else rights[idx]=next;
 return {...prev,rights};});
 const saveRoleForm=async()=>{if(!role)return;
 if(!/^[A-Z0-9_-]{2,32}$/.test(trim(role.code).toUpperCase())||trim(role.name).length<3){setError('Enter a valid role code and name.');return}
 const ok=await run(()=>saveRole({...role,rights:role.rights.filter(item=>ACTIONS.some(a=>item[a]))}),'Role permissions saved to Supabase.');if(ok)setRole(null);};
 const closeEmployeeEditor=()=>{setUser(null);setInviting(false);setEmployeePassword({...blankPasswordFields});setShowEmployeePassword(false);setError('');};
 const beginEmployeeInvite=()=>{setInviting(true);setInvitation({...blankInvitation});setEmployeePassword({...blankPasswordFields});setShowEmployeePassword(false);setUser(null);setError('');};
 const selectUser=p=>{setInviting(false);setError('');setEmployeePassword({...blankPasswordFields});setShowEmployeePassword(false);setUser({...p,department_id:p.department_id||'',role_ids:(data.user_roles||[]).filter(x=>x.user_id===p.user_id).map(x=>x.role_id)})};
 const saveUserForm=async()=>{if(!user)return;
 if(trim(user.display_name).length<2 || (user.active&&!user.role_ids.length)){setError('Enter a name and select at least one role for an active user.');return}
 const wasDisabled=(data.users||[]).some(p=>p.user_id===user.user_id&&!p.active);
 const ok=await run(async()=>{if(wasDisabled&&user.active)await restoreEmployeeLogin(user.user_id);await saveUser(user);},'Login role and access saved to Supabase.');if(ok)setUser(null);};
 const isAdminRoleSelected=ids=>(data?.roles||[]).some(r=>ids.includes(r.id)&&(r.code==='ADMIN'||r.system_role));
 const passwordIssue=({password,confirm},allowEmpty=false)=>temporaryPasswordIssue(password,confirm,{allowEmpty});
 const sendInvitation=async()=>{
  const email=trim(invitation.email).toLowerCase();
  if(!/^\S+@\S+\.\S+$/.test(email)||!invitation.role_ids.length){setError('Enter a valid email and choose one role.');return;}
  const issue=passwordIssue(employeePassword);
  if(issue){setError(issue);return;}
  const ok=await run(()=>inviteUser({email,role_ids:invitation.role_ids,password:employeePassword.password}),
   'Login created and verified in Supabase Auth. The selected ERP role is saved.',true);
  if(ok){setInviting(false);setInvitation({...blankInvitation});setEmployeePassword({...blankPasswordFields});setShowEmployeePassword(false);}
 };
 const resetCustomPassword=async()=>{
  if(!user||!user.active){setError('Select an enabled account before resetting the password.');return;}
  const issue=passwordIssue(employeePassword);
  if(issue){setError(issue);return;}
  if(!await askConfirmation(`Replace the login password for ${user.email}? The previous password will stop working.`))return;
  const ok=await run(()=>resetEmployeeLogin(user.user_id,employeePassword.password),'Password updated in Supabase Auth.',true);
  if(ok){setEmployeePassword({...blankPasswordFields});setShowEmployeePassword(false);}
 };
 const isAdminEmployee=p=>(data?.user_roles||[]).some(link=>link.user_id===p.user_id&&(data?.roles||[]).some(r=>r.id===link.role_id&&(r.code==='ADMIN'||r.system_role)));
 const addConnection=()=>{if(!newMap.from||!newMap.to||newMap.from===newMap.to){setError('Choose two different workflow modules.');return}
 if(template.edges.some(e=>e.source_page===newMap.from)){setError('That source already has a next step. Edit or remove its existing connection first.');return}
 setTemplate(t=>({...t,edges:[...t.edges,{source_page:newMap.from,target_page:newMap.to,gate_statuses:[],field_map:{}}]}));setNewMap({from:'',to:''});setError('');};
 const toggleRoleId=(ids,id)=>ids.includes(id)?ids.filter(x=>x!==id):[...ids,id];
 const selectInviteRole=id=>{setInvitation(v=>({...v,role_ids:id?[id]:[]}));setError('');};
 const unmapped=storageKeys.filter(key=>key.startsWith('dfab-')&&key!=='dfab-workflow-links-v1'&&!data?.storage?.some(m=>m.storage_key===key));
 if(loading&&!data)return <main className="content page-shell admin-root"><h1>Admin Control Center</h1><div className="admin-loading"><LoaderCircle className="admin-spin"/> Loading controlled workspace from Supabase…</div>{error&&<Status type="error">{error} <button onClick={load}>Retry</button></Status>}</main>;
 if(!data)return <main className="content page-shell admin-root"><h1>Admin Control Center</h1><Status type="error">{error||'Admin setup is not available.'}</Status><Button onClick={load}><RefreshCw size={15}/> Retry connection</Button></main>;
 return <main className="content page-shell admin-root admin-simple" data-layout="admin-console">
  <aside className="admin-console-sidebar" aria-label="Administration navigation">
   <div className="admin-console-brand"><span className="admin-console-brand-icon"><ShieldCheck size={22}/></span><span><b>Control Center</b><small>DFAB OneERP · Admin</small></span></div>
   <nav className="admin-console-navigation" aria-label="Admin sections">
    <button type="button" className={`admin-console-dashboard ${tab===dashboardTab?'active':''}`} aria-current={tab===dashboardTab?'page':undefined} onClick={()=>navigateTab(dashboardTab)}><LayoutDashboard size={18}/><span>{dashboardLabel}</span></button>
    {ADMIN_NAV_GROUPS.map(group=><section key={group.id} className="admin-console-group">
     <button className="admin-console-group-heading" type="button" aria-expanded={Boolean(expandedGroups[group.id])} aria-controls={`admin-submenu-${group.id}`} onClick={()=>setExpandedGroups(prev=>({...prev,[group.id]:!prev[group.id]}))}><group.icon size={17}/><span>{group.label}</span><ChevronDown size={16} className={expandedGroups[group.id]?'expanded':''}/></button>
     {expandedGroups[group.id]&&<div id={`admin-submenu-${group.id}`} className="admin-console-submenu">{group.items.map(([id,label,Icon])=><button key={id} type="button" className={tab===id?'active':''} aria-current={tab===id?'page':undefined} onClick={()=>navigateTab(id)}><Icon size={16}/><span>{label}</span>{id==='users'&&data?.users&&<small>{data.users.length}</small>}</button>)}</div>}
    </section>)}
   </nav>
   
  </aside>
  <div className="admin-console-content">
  <header className="admin-title-row admin-simple-heading">
   <div>
    <span className="admin-eyebrow">DFAB ONEERP / ADMIN</span>
    <h1>{tab==='overview'?'Dashboard':({users:'Saved logins',departments:'Departments',roles:'Roles & permissions',workflows:'Document flows',lineage:'Data connections',audit:'Activity history',storage:'Advanced settings'})[tab]||'Administration'}</h1>
   </div>
   <Button secondary onClick={load} disabled={saving||loading}><RefreshCw size={16}/> Refresh data</Button>
  </header>


  {error&&<Status type="error">{error}</Status>}
  {message&&<Status>{message}</Status>}
  {data.users.filter(p=>p.active&&(data.user_roles||[]).some(ur=>ur.user_id===p.user_id&&data.roles.some(r=>r.id===ur.role_id&&r.code==='ADMIN'))).length>1&&
   <div className="admin-warning"><ShieldCheck size={19}/><span><b>Admin access review:</b> Several employees have full Administrator access. Check their roles before more departments begin using the ERP.</span><button type="button" onClick={()=>navigateTab('users')}>Review employees</button></div>}

  {tab==='overview'&&<>
   <section className="admin-overview-intro" aria-label="Getting started">
    <div>
     <span className="admin-section-kicker">OVERVIEW</span>
     <h2>Company administration</h2>
     <p>Select a section from the left navigation to manage your ERP.</p>
    </div>
    <span className="admin-connected"><Check size={15}/> Admin data loaded</span>
   </section>
   <div className="admin-summary">
    <div><Users size={20}/><span>Employees</span><strong>{data.users.length}</strong></div>
    <div><Layers3 size={20}/><span>Departments</span><strong>{data.departments.length}</strong></div>
    <div><ShieldCheck size={20}/><span>Access roles</span><strong>{data.roles.length}</strong></div>
    <div><GitBranch size={20}/><span>Document links</span><strong>{connectedCount}</strong></div>
   </div>
  </>}

  {tab==='users'&&<>
   <div className="admin-section-title"><div><span className="admin-section-kicker">TEAM & ACCESS</span><h2>Logins</h2><p>Manage who can sign in to ERP. Account passwords are kept in Supabase Auth, not the employee directory.</p></div></div>
   <div className={`admin-panel-layout admin-employee-workspace ${inviting||user?'admin-workspace-editing':''}`}>
    {!inviting&&!user&&<Card title={`Login accounts · ${data.users.filter(p=>p.active).length}`} description="Saved ERP accounts with their assigned roles. Disabled accounts can be shown for audit purposes.">
     <div className="admin-tools admin-list-toolbar">
      <Button onClick={beginEmployeeInvite} disabled={saving}><UserPlus size={16}/> Add login</Button>
      <label className="admin-search"><Search size={16}/><input aria-label="Search login accounts" placeholder="Search email" value={filter} onChange={e=>setFilter(e.target.value)}/></label>
      <label className="admin-check admin-filter-toggle"><input type="checkbox" checked={showInactive} onChange={e=>setShowInactive(e.target.checked)}/> Show disabled</label>
     </div>
     <div className="admin-table-wrap"><table><thead><tr><th>Email</th><th>Role</th><th>Access</th><th>Actions</th></tr></thead><tbody>
      {data.users.filter(p=>(showInactive||p.active)&&matchesSearch([p.email,p.display_name],filter)).map(p=><tr key={p.user_id}>
       <td><b>{p.email}</b></td>
       <td>{(data.user_roles||[]).filter(ur=>ur.user_id===p.user_id).map(ur=>data.roles.find(r=>r.id===ur.role_id)?.name).filter(Boolean).join(', ')||'Not assigned'}</td>
       <td><span className={`admin-state ${p.active?'is-active':'is-disabled'}`}>{p.active?'Enabled':'Disabled'}</span></td>
       <td><div className="admin-inline-actions"><Button secondary disabled={saving} onClick={()=>selectUser(p)} aria-label={`Edit ${p.email}`}>Edit</Button>{p.active&&<Button secondary disabled={saving} onClick={()=>deleteLogin(p)} aria-label={`Delete login ${p.email}`}><Trash2 size={14}/> Delete</Button>}</div></td>
      </tr>)}
     </tbody></table></div>
     {!data.users.filter(p=>(showInactive||p.active)&&matchesSearch([p.email,p.display_name],filter)).length&&<Empty>No login accounts match.</Empty>}
    </Card>}
    {(inviting||user)&&<Card editor onClose={closeEmployeeEditor} busy={saving} feedback={error} title={inviting?'Add login':`Edit login · ${user?.email||''}`} description={inviting?'Enter the email, select one ERP role and set the password. All three are required.':'Change this account’s ERP role or enter a new password to reset its Supabase Auth credentials.'}>
     <div className="admin-form-grid admin-login-simple-form">
      <label><span className="admin-label-text">Email <i className="admin-required">*</i></span><input type="email" autoComplete="email" maxLength={254} disabled={!inviting} value={inviting?invitation.email:user.email||''} onChange={e=>inviting&&setInvitation(v=>({...v,email:e.target.value}))} placeholder="employee@company.com"/></label>
      <label><span className="admin-label-text">Role <i className="admin-required">*</i></span>
       <Select value={inviting?invitation.role_ids[0]||'':user.role_ids[0]||''} onChange={e=>inviting?selectInviteRole(e.target.value):setUser(v=>({...v,role_ids:e.target.value?[e.target.value]:[]}))}>
        <option value="">Select role</option>{data.roles.filter(r=>r.active||(!inviting&&user?.role_ids.includes(r.id))).map(r=><option key={r.id} value={r.id}>{r.name}{r.active?'':' (disabled)'}</option>)}
       </Select>
       {activeLoginRole&&<small className="admin-role-access-summary" role="status">{selectedRoleAccess}{!activeLoginRole.active?' · This role is disabled; choose an active role for new logins.':''}</small>}
       {data.roles.filter(r=>r.active).length===1&&data.roles.some(r=>r.code==='ADMIN')&&<small className="admin-role-setup-hint" role="status">Only Administrator exists in Supabase. Install the Admin Department Roles migration, then refresh this panel. Existing roles and permissions are not replaced.</small>}
      </label>
      <label><span className="admin-label-text">{inviting?'Set password':'New password (optional)'} {inviting&&<i className="admin-required">*</i>}</span><input type={showEmployeePassword?'text':'password'} autoComplete="new-password" minLength={12} maxLength={128} value={employeePassword.password} onChange={e=>setEmployeePassword(v=>({...v,password:e.target.value}))} placeholder="12+ characters with letters and numbers"/></label>
      <label><span className="admin-label-text">Confirm password {inviting&&<i className="admin-required">*</i>}</span><input type={showEmployeePassword?'text':'password'} autoComplete="new-password" minLength={12} maxLength={128} value={employeePassword.confirm} onChange={e=>setEmployeePassword(v=>({...v,confirm:e.target.value}))} placeholder="Repeat password"/></label>
     </div>
     <label className="admin-check admin-reveal-password"><input type="checkbox" checked={showEmployeePassword} onChange={e=>setShowEmployeePassword(e.target.checked)}/> Show passwords</label>
     {(employeePassword.password||employeePassword.confirm)&&<p role="status" className={`admin-password-validator ${passwordIssue(employeePassword)?'invalid':'valid'}`}>{passwordIssue(employeePassword)||'Passwords match.'}</p>}
     {!inviting&&<div className="admin-login-edit-actions"><label className="admin-check"><input type="checkbox" checked={Boolean(user.active)} onChange={e=>setUser(v=>({...v,active:e.target.checked}))}/> Enable ERP access</label><Button secondary disabled={saving||!employeePassword.password||!employeePassword.confirm} onClick={resetCustomPassword}>Update password</Button></div>}
     <p className="admin-help">Only the password saved in Supabase Auth will work. Passwords are never displayed or stored in ERP records. Password changes are separate from role updates.</p>
     <div className="admin-form-footer admin-editor-actions"><Button secondary disabled={saving} onClick={closeEmployeeEditor}>Cancel</Button><Button busy={saving} onClick={inviting?sendInvitation:saveUserForm}><Save size={16}/>{inviting?'Create login':'Save role and access'}</Button></div>
    </Card>}
   </div>
  </>}

  {tab==='departments'&&<>
   <div className="admin-section-title"><div><span className="admin-section-kicker">COMPANY STRUCTURE</span><h2>Departments</h2><p>Keep your Sales, Stores, Production, Quality and other teams organized.</p></div></div>
   <div className={`admin-panel-layout ${department?'admin-workspace-editing':''}`}>
    <Card title="Your departments" description="Edit an existing department or add another one. You cannot delete a department that still has linked employees or records.">
     <div className="admin-tools"><Button onClick={()=>{setDepartment({...blankDepartment});setError('')}}><Plus size={16}/> Add department</Button></div>
     <div className="admin-table-wrap"><table><thead><tr><th>Department</th><th>Code</th><th>Cost centre</th><th>Status</th><th>Manage</th></tr></thead><tbody>
      {data.departments.map(d=><tr key={d.id}><td><b>{d.name}</b></td><td>{d.code}</td><td>{d.cost_center||'—'}</td><td><span className={`admin-state ${d.active?'is-active':'is-disabled'}`}>{d.active?'Active':'Disabled'}</span></td><td><div className="admin-inline-actions"><Button secondary onClick={()=>{setDepartment({...d});setError('')}}>Edit</Button><Button secondary disabled={saving} onClick={()=>removeDepartment(d)}><Trash2 size={15}/> Delete</Button></div></td></tr>)}
     </tbody></table></div>{!data.departments.length&&<Empty>No departments yet. Add your first department.</Empty>}
    </Card>
    {department&&<Card editor onClose={()=>setDepartment(null)} busy={saving} feedback={error} title={department.id?'Edit department':'Add department'} description="Enter the basic details and save. Code is the short department identifier.">
     <div className="admin-form-grid"><label>Department name<input value={department.name} onChange={e=>setDepartment({...department,name:e.target.value})} placeholder="For example, Production"/></label><label>Department code<input maxLength={24} value={department.code} onChange={e=>setDepartment({...department,code:e.target.value.toUpperCase()})} placeholder="PROD"/></label><label>Cost centre (optional)<input value={department.cost_center||''} onChange={e=>setDepartment({...department,cost_center:e.target.value})} placeholder="For example, CC-01"/></label><label className="admin-check"><input type="checkbox" checked={department.active} onChange={e=>setDepartment({...department,active:e.target.checked})}/> Department is active</label></div>
     <div className="admin-form-footer"><Button secondary onClick={()=>setDepartment(null)}>Cancel</Button><Button busy={saving} onClick={saveDepartmentForm}><Save size={16}/> Save department</Button></div>
    </Card>}
   </div>
  </>}

  {tab==='roles'&&<>
   <div className="admin-section-title"><div><span className="admin-section-kicker">SECURITY</span><h2>Who can do what?</h2><p>Each role controls which modules an employee can open and what actions they can perform.</p></div></div>
   <div className={`admin-panel-layout ${role?'admin-workspace-editing':''}`}>
    <Card title="Access roles" description="Assign roles to employees in the Employees section. The built-in Administrator role is protected.">
     <div className="admin-tools"><Button onClick={()=>{setRole({...blankRole});setError('')}}><Plus size={16}/> Add role</Button></div>
     <div className="admin-list">{data.roles.map(r=><div key={r.id} className="admin-list-item"><div><b>{r.name}</b><small>{r.code} · {r.active?'Active':'Disabled'} · {(data.rights||[]).filter(x=>x.role_id===r.id).length} modules</small></div>{r.system_role||r.code==='ADMIN'?<span className="admin-chip">Protected</span>:<div className="admin-inline-actions"><Button secondary onClick={()=>selectRole(r)}>Edit permissions</Button><Button secondary disabled={saving} onClick={()=>removeRole(r)}><Trash2 size={15}/> Delete</Button></div>}</div>)}{!data.roles.length&&<Empty>No roles yet. Add a role to decide access.</Empty>}</div>
    </Card>
    {role&&<Card editor onClose={()=>setRole(null)} busy={saving} feedback={error} title={role.id?`Edit ${role.name} permissions`:'Add an access role'} description="Choose what this group of employees can do. Changes are saved only when you click Save.">
     <div className="admin-form-grid"><label>Role name<input value={role.name} onChange={e=>setRole({...role,name:e.target.value})} placeholder="For example, Stores Team"/></label><label>Role code<input value={role.code} onChange={e=>setRole({...role,code:e.target.value.toUpperCase()})} placeholder="STORES"/></label><label>Description (optional)<input value={role.description||''} onChange={e=>setRole({...role,description:e.target.value})}/></label><label className="admin-check"><input type="checkbox" checked={role.active} onChange={e=>setRole({...role,active:e.target.checked})}/> Role is active</label></div>
     <div className="admin-step-caption">MODULE ACCESS</div>
     <p className="admin-help">Tick View to open a module. Tick Add, Edit, Delete, Approve or Export only where needed. Advanced rights also enable View.</p>
     <div className="admin-tools"><label className="admin-filter-label">Department / module group<Select value={roleGroup} onChange={e=>setRoleGroup(e.target.value)}>{groups.map(g=><option key={g}>{g}</option>)}</Select></label><label className="admin-search"><Search size={16}/><input value={filter} placeholder="Find a module" onChange={e=>setFilter(e.target.value)}/></label></div>
     <div className="admin-table-wrap admin-permission-table"><table><thead><tr><th>ERP module</th>{ACTIONS.map(a=><th key={a} title={a==='view'?'Can open this screen':a==='create'?'Can add new records':a==='approve'?'Can approve documents':`Can ${a} records`}>{({view:'View',create:'Add',edit:'Edit',delete:'Delete',approve:'Approve',export:'Export'})[a]}</th>)}</tr></thead><tbody>{filteredCatalog.map(c=>{const r=role.rights.find(x=>x.page===c.page)||{};return <tr key={c.page}><td><b>{c.page}</b><small>{c.module_group}</small></td>{ACTIONS.map(a=><td key={a}><input type="checkbox" aria-label={`${a} ${c.page}`} checked={Boolean(r[a])} onChange={e=>setRolePermission(c.page,a,e.target.checked)}/></td>)}</tr>})}</tbody></table></div>
     <div className="admin-form-footer"><Button secondary onClick={()=>setRole(null)}>Cancel</Button><Button busy={saving} onClick={saveRoleForm}><Save size={16}/> Save permissions</Button></div>
    </Card>}
   </div>
  </>}

  {tab==='workflows'&&<>
   <div className="admin-section-title"><div><span className="admin-section-kicker">DOCUMENT CONNECTIONS</span><h2>Where does each document go next?</h2><p>See the current steps first. If you need a different route, make a draft and publish it after checking.</p></div></div>
   <section className="admin-auto-flow-card" aria-label="Generate standard ERP document connections">
    <div><span className="admin-section-kicker">AUTOMATIC FLOW BUILDER</span><h3>Build all existing ERP document links</h3>
     <p>Uses the source-to-next definitions already registered in this ERP. Copies compatible fields and retains the server-approved status gates. It does not generate documents or change live settings until you Save and Publish.</p>
     <div className="admin-auto-flow-stats"><span><strong>{generated.edges.length}</strong> valid connections</span><span><strong>{generated.matchedFields}</strong> safe field mappings</span><span><strong>{generated.groups.length}</strong> workflow groups</span></div>
     {generated.skipped.length>0&&<p className="admin-auto-flow-warning" role="alert">{generated.skipped.length} invalid catalog connections require correction before automation.</p>}
     {generated.error&&<p className="admin-auto-flow-warning" role="alert">{generated.error}</p>}
    </div><Button onClick={buildAutomaticTemplate} disabled={saving||Boolean(generated.error)||Boolean(generated.skipped.length)||!generated.edges.length}><GitBranch size={16}/> Generate all flows</Button>
   </section>
   <div className={`admin-panel-layout admin-workflow-layout ${template?'admin-workflow-editing':''}`}>
    <Card title="Current document flows" description={activeTemplate?`Active flow: ${activeTemplate.name}`:'Using the built-in ERP workflow'}>
     <div className="admin-flow-toolbar"><span className="admin-chip published"><Check size={14}/> {connectedCount} connections active</span><Button secondary onClick={reset} disabled={!activeTemplate||saving}>Use original flow</Button></div>
     <div className="admin-tools"><label className="admin-search"><Search size={16}/><input aria-label="Search document connections" value={filter} onChange={e=>{setFilter(e.target.value);setShowAllConnections(false)}} placeholder="Find a document"/></label><label className="admin-filter-label">Group<Select value={roleGroup} onChange={e=>{setRoleGroup(e.target.value);setShowAllConnections(false)}}>{groups.map(g=><option key={g}>{g}</option>)}</Select></label></div>
     <div className="admin-flow-map">{visibleConnections.length?visibleConnections.slice(0,showAllConnections?undefined:8).map((e,i)=><div className="admin-flow-row" key={`${e.source_page}-${i}`}><span className="flow-node">{e.source_page}</span><ArrowRight size={17}/><span className="flow-node destination">{e.target_page}</span>{e.gate_statuses?.length>0&&<small>{e.gate_statuses.join(', ')}</small>}</div>):<Empty>No matching connections. Clear the search or choose another group.</Empty>}</div>
     {visibleConnections.length>8&&<Button secondary onClick={()=>setShowAllConnections(v=>!v)}>{showAllConnections?'Show fewer connections':`Show all ${visibleConnections.length} connections`}</Button>}
    </Card>
    <Card title="Change a document flow" description="Changing a draft does not change your live ERP. Only Publish activates it.">
     {!template?<>
      <div className="admin-workflow-help"><b>How to change a flow</b><span>1. Create a draft from current connections.</span><span>2. Change the steps and save the draft.</span><span>3. Publish it when you are ready.</span></div>
      <Button onClick={beginNewTemplate}><Plus size={16}/> Create workflow draft</Button>
      <div className="admin-list">{data.templates.map(t=><div className="admin-list-item" key={t.id}><div><b>{t.name}</b><small>{t.status==='published'?'Active workflow':`Draft · version ${t.version}`} · {listForTemplate(t,data).length} connections</small></div><div className="admin-inline-actions">{t.status==='draft'?<><Button secondary onClick={()=>editTemplate(t)}><FileCheck2 size={15}/> Edit</Button><Button disabled={saving} onClick={()=>publish(t)}>Publish</Button><Button secondary disabled={saving} onClick={()=>removeTemplate(t)}><Trash2 size={15}/> Delete</Button></>:<span className="admin-chip published"><Check size={14}/> Active</span>}</div></div>)}{!data.templates.length&&<Empty>No saved workflows yet. The built-in flow remains active.</Empty>}</div>
     </>:<div className="admin-editor">
      <div className="admin-editor-heading"><Button secondary onClick={()=>setTemplate(null)}><ArrowLeft size={16}/> Back to drafts</Button><b>{template.id?'Edit workflow draft':'New workflow draft'}</b></div>
      <div className="admin-draft-notice" role="status"><ShieldCheck size={17}/> Draft only. Review the connections, then Save draft. Publishing the saved draft activates these routes for subsequent document handoffs.</div>
      <div className="admin-form-grid"><label>Draft name<input maxLength={100} value={template.name} onChange={e=>setTemplate({...template,name:e.target.value})} placeholder="For example, Approved purchase flow"/></label><label>Notes (optional)<input maxLength={500} value={template.description} onChange={e=>setTemplate({...template,description:e.target.value})} placeholder="Why this workflow is needed"/></label></div>
      <div className="admin-step-caption">CONNECTED DOCUMENTS</div>
      <p className="admin-help">Each row shows the document that opens next. Open “Settings” only if you need to change the required status or automatic field filling.</p>
      <div className="admin-list">{template.edges.map((edge,index)=>{const src=workflowPages.find(p=>p.page===edge.source_page);const dest=workflowPages.find(p=>p.page===edge.target_page);return <div key={`${edge.source_page}-${index}`} className="admin-edge-editor">
       <div className="admin-edge-top"><b>{edge.source_page} <ArrowRight size={14}/> {edge.target_page}</b><button type="button" className="admin-icon-button" onClick={()=>setTemplate(t=>({...t,edges:t.edges.filter((_,i)=>i!==index)}))} aria-label={`Remove connection ${edge.source_page}`} title="Remove this connection"><Trash2 size={16}/></button></div>
       <details className="admin-edge-details"><summary>Settings: required status and auto-fill</summary>
        <label>Allow next step when status is <Select value="" onChange={e=>{const value=e.target.value;if(!value)return;setTemplate(t=>({...t,edges:t.edges.map((x,i)=>i===index?{...x,gate_statuses:x.gate_statuses.includes(value)?x.gate_statuses.filter(s=>s!==value):[...x.gate_statuses,value]}:x)}))}}><option value="">Select a status to add/remove</option>{(src?.statuses||[]).map(s=><option key={s}>{s}</option>)}</Select></label>
        {edge.gate_statuses?.length>0&&<div className="admin-chip-list">{edge.gate_statuses.map(s=><button type="button" key={s} onClick={()=>setTemplate(t=>({...t,edges:t.edges.map((x,i)=>i===index?{...x,gate_statuses:x.gate_statuses.filter(v=>v!==s)}:x)}))}>{s} <X size={12}/></button>)}</div>}
        <div className="admin-form-grid"><label>Copy field from source<Select value={newMap[`source-${index}`]||''} onChange={e=>setNewMap(n=>({...n,[`source-${index}`]:e.target.value}))}><option value="">Choose source field</option>{(src?.columns||[]).map(f=><option key={f}>{f}</option>)}</Select></label><label>Into field in next document<Select value={newMap[`target-${index}`]||''} onChange={e=>setNewMap(n=>({...n,[`target-${index}`]:e.target.value}))}><option value="">Choose target field</option>{(dest?.fields||[]).map(f=><option key={f}>{f}</option>)}</Select></label></div>
        <Button secondary onClick={()=>{const from=newMap[`source-${index}`],to=newMap[`target-${index}`];if(!from||!to){setError('Choose both fields before adding a mapping.');return}setTemplate(t=>({...t,edges:t.edges.map((x,i)=>i===index?{...x,field_map:{...x.field_map,[to]:from}}:x)}));setNewMap(n=>({...n,[`source-${index}`]:'',[`target-${index}`]:''}));setError('')}}><Plus size={15}/> Add auto-fill rule</Button>
        {Object.entries(edge.field_map||{}).length>0&&<div className="admin-chip-list">{Object.entries(edge.field_map).map(([to,from])=><button type="button" key={to} title="Remove auto-fill rule" onClick={()=>setTemplate(t=>({...t,edges:t.edges.map((x,i)=>{if(i!==index)return x;const m={...x.field_map};delete m[to];return {...x,field_map:m}})}))}>{from} → {to} <X size={12}/></button>)}</div>}
       </details>
      </div>})}</div>
      <div className="admin-step-caption">ADD A CONNECTION</div>
      <div className="admin-form-grid"><label>From document<Select value={newMap.from} onChange={e=>setNewMap(n=>({...n,from:e.target.value}))}><option value="">Choose source document</option>{workflowPages.map(c=><option key={c.page}>{c.page}</option>)}</Select></label><label>Next document<Select value={newMap.to} onChange={e=>setNewMap(n=>({...n,to:e.target.value}))}><option value="">Choose next document</option>{workflowPages.filter(c=>c.page!==newMap.from).map(c=><option key={c.page}>{c.page}</option>)}</Select></label></div>
      <div className="admin-form-footer"><Button secondary onClick={addConnection}><Plus size={15}/> Add connection</Button><Button busy={saving} onClick={saveCurrentTemplate}><Save size={16}/> Save draft</Button></div>
     </div>}
    </Card>
   </div>
  </>}

  {tab==='lineage'&&<>
   <div className="admin-section-title"><div><span className="admin-section-kicker">LIVE DATA CONNECTIONS</span><h2>Where is each entry used?</h2><p>Select any ERP document to see which saved section holds it, where it moves next and which fields can carry forward.</p></div></div>
   <section className="admin-flow-guide" aria-label="How data moves"><div><span className="admin-flow-guide-step">1</span><b>Enter and save</b><small>Data is saved in the document's Supabase-backed section.</small></div><ArrowRight size={20}/><div><span className="admin-flow-guide-step">2</span><b>Approve and connect</b><small>The next step is created only after its workflow checks pass.</small></div><ArrowRight size={20}/><div><span className="admin-flow-guide-step">3</span><b>Auto-fill and report</b><small>Related fields and reports read the saved records.</small></div></section>
   <div className="admin-lineage-grid">
    <Card title="Choose a document" description="Modules from the existing ERP, not invented sample workflows.">
     <label className="admin-search admin-lineage-search"><Search size={16}/><input aria-label="Find ERP document" value={filter} onChange={e=>setFilter(e.target.value)} placeholder="Search documents, modules or groups"/></label>
     <div className="admin-lineage-picker" role="listbox" aria-label="ERP document source">
      {workflowPages.filter(c=>matchesSearch([c.page,c.module_group],filter)).map(c=><button type="button" role="option" aria-selected={inspected?.page===c.page} key={c.page} className={inspected?.page===c.page?'selected':''} onClick={()=>setInspectedPage(c.page)}><span><b>{c.page}</b><small>{c.module_group}</small></span><ArrowRight size={16}/></button>)}
      {!workflowPages.some(c=>matchesSearch([c.page,c.module_group],filter))&&<Empty>No matching document. Clear the search.</Empty>}
     </div>
    </Card>
    <div className="admin-lineage-details" aria-live="polite">
     {inspected?<>
      <section className="admin-lineage-focus"><div><span>SELECTED ERP DOCUMENT</span><h3>{inspected.page}</h3><p>{inspected.group} · {inspected.fields.length} existing form fields</p></div><span className="admin-connected"><Check size={15}/> Current catalog</span></section>
      <Card title="1. Where the entry is saved" description="These counts come from the authenticated ERP snapshot. They are not demonstration figures.">
       {inspected.stores.length?<div className="admin-store-list">{inspected.stores.map(item=><div key={item.key}><span><Database size={16}/><b>{item.key}</b></span><strong>{item.count===null?'Mapped':`${item.count.toLocaleString('en-IN')} saved`}</strong></div>)}</div>:<div className="admin-context-note">No matching saved section was found in this session. Saving a new record requires the existing ERP storage mapping and Supabase permissions.</div>}
      </Card>
      <Card title="2. Which documents are connected" description="Connections are read from the active published template, or the built-in ERP catalog when none is published.">
       {inboundConnections.length>0&&<div className="admin-lineage-inbound"><span>Receives data from</span><div>{inboundConnections.map(e=><button key={e.source_page} type="button" onClick={()=>setInspectedPage(e.source_page)}>{e.source_page}<ArrowRight size={14}/></button>)}</div></div>}
       {inspected.links.length?inspected.links.map(link=><div className="admin-lineage-hop" key={link.destination}>
        <div className="admin-flow-row"><span className="flow-node">{inspected.page}</span><ArrowRight size={18}/><span className="flow-node destination">{link.destination}</span></div>
        <div className="admin-lineage-subheading">Field transfer explanation</div>
        {link.transfers.length?<div className="admin-lineage-maps">{link.transfers.map(item=><div key={`${item.target}-${item.source}`}><span>{item.source}</span><ArrowRight size={15}/><b>{item.target}</b><small>{item.kind==='configured'?'Admin-configured mapping':'Matching field name'}</small></div>)}</div>:<p className="admin-help">No explicit or same-name field pairs are configured for this connection. Other built-in reference lookups may still apply.</p>}
        {link.gate_statuses?.length>0&&<p className="admin-gate-note"><ShieldCheck size={15}/> Required document status: {link.gate_statuses.join(' or ')}</p>}
       </div>):<Empty>This document has no next-document connection configured.</Empty>}
       <div className="admin-context-note">A visible connection is not a posted transaction. Creation still requires an authorized user, a valid source record and successful database confirmation.</div>
      </Card>
      <Card title="3. Reports that use these records" description="Only report sources declared in the existing i-MANTRA integration are listed here.">
       {inspected.reports.length?<div className="admin-report-chips">{inspected.reports.map(name=><span key={name}><ClipboardList size={14}/>{name}</span>)}</div>:<Empty>No source-specific i-MANTRA report definition is registered for this document.</Empty>}
      </Card>
      <div className="admin-lineage-action"><Button secondary onClick={()=>{navigateTab('workflows');setFilter(inspected.page);setShowAllConnections(true)}}><GitBranch size={16}/> View or edit this connection</Button></div>
     </>:<Empty>No documents with fields found in the ERP catalog.</Empty>}
    </div>
   </div>
  </>}

  {tab==='audit'&&<>
   <div className="admin-section-title"><div><span className="admin-section-kicker">HISTORY</span><h2>Recent admin activity</h2><p>Check which administrator changed users, departments, permissions or document flows.</p></div></div>
   <Card title="Saved activity" description="These entries come from the ERP database and cannot be edited here.">
    <div className="admin-table-wrap"><table><thead><tr><th>When</th><th>What changed</th><th>Record</th><th>Changed by</th></tr></thead><tbody>{data.events.map(e=><tr key={e.id}><td>{dateTime(e.created_at)}</td><td>{e.event.replaceAll('_',' ')}</td><td>{e.target}</td><td>{data.users.find(u=>u.user_id===e.actor_id)?.display_name||e.actor_id||'System'}</td></tr>)}</tbody></table></div>
    {!data.events.length&&<Empty>No administrator changes have been recorded yet.</Empty>}
   </Card>
  </>}

  {tab==='storage'&&<>
   <div className="admin-section-title"><div><span className="admin-section-kicker">ADVANCED · FOR SYSTEM ADMINISTRATORS</span><h2>Database access settings</h2><p>Most teams never need this section. It controls which ERP screen owns each saved data collection.</p></div></div>
   <div className="admin-warning"><ShieldCheck size={19}/><span>Changing a mapping can affect other departments' ability to read or save records. Change it only when you know the matching ERP module.</span></div>
   <div className="admin-panel-layout">
    <Card title="Saved data section mappings" description={`${data.storage.length} sections mapped · ${unmapped.length} existing sections without a mapping`}>
     <div className="admin-table-wrap"><table><thead><tr><th>Data section</th><th>ERP module</th><th>Row index</th><th>Status index</th><th>Action</th></tr></thead><tbody>{data.storage.map(s=><tr key={s.storage_key}><td>{s.storage_key}</td><td>{s.page}</td><td>{s.record_key_index}</td><td>{s.status_index}</td><td><Button secondary disabled={saving} onClick={()=>removeStorageMap(s)}><Trash2 size={15}/> Remove</Button></td></tr>)}</tbody></table></div>
     {!data.storage.length&&<Empty>No storage ownership mappings have been configured.</Empty>}
    </Card>
    <Card title="Add or update a mapping" description="Choose the saved data section and the ERP module that should be allowed to use it.">
     <div className="admin-form-grid"><label>Saved data section<Select value={mapping.storage_key} onChange={e=>{const known=data.storage.find(s=>s.storage_key===e.target.value);setMapping(m=>({...m,storage_key:e.target.value,page_name:known?.page||m.page_name,record_key_index:known?.record_key_index??0,status_index:known?.status_index??-1}))}}><option value="">Choose section</option>{[...new Set([...storageKeys,...data.storage.map(x=>x.storage_key)])].filter(x=>x.startsWith('dfab-')&&x!=='dfab-workflow-links-v1').sort().map(key=><option key={key}>{key}</option>)}</Select></label><label>ERP module<Select value={mapping.page_name} onChange={e=>setMapping({...mapping,page_name:e.target.value})}><option value="">Choose module</option>{data.catalog.map(c=><option key={c.page}>{c.page}</option>)}</Select></label></div>
     <details className="admin-advanced-details"><summary>Technical column indexes</summary><div className="admin-form-grid"><label>Record ID column index<input type="number" min="0" max="24" value={mapping.record_key_index} onChange={e=>setMapping({...mapping,record_key_index:Number(e.target.value)})}/></label><label>Status column index (-1 = none)<input type="number" min="-1" max="24" value={mapping.status_index} onChange={e=>setMapping({...mapping,status_index:Number(e.target.value)})}/></label></div></details>
     <div className="admin-form-footer"><Button busy={saving} onClick={async()=>{if(!mapping.storage_key||!mapping.page_name){setError('Choose a data section and its owning ERP page.');return}if(!await askConfirmation(`Map ${mapping.storage_key} to ${mapping.page_name}? This updates access for all users.`))return;await run(()=>registerStorage(mapping),'Storage permission mapping saved.');}}><Save size={16}/> Save mapping</Button></div>
    </Card>
   </div>
  </>}
  {adminNotice&&<div key={adminNotice.id} className={`admin-console-toast ${adminNotice.kind}`} role={adminNotice.kind==='error'?'alert':'status'} aria-live={adminNotice.kind==='error'?'assertive':'polite'}>
   {adminNotice.kind==='error'?<AlertCircle size={21}/>:<CheckCircle2 size={21}/>}
   <span><b>{adminNotice.kind==='error'?'Action not completed':'Saved successfully'}</b><small>{adminNotice.text}</small></span>
   <button type="button" aria-label="Dismiss notification" onClick={()=>setAdminNotice(null)}><X size={17}/></button>
  </div>}
  </div>
 </main>;
}
