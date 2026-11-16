import React, {useMemo, useState} from 'react';
import {ArrowLeft,ArrowRight,Check,ClipboardList,Database,GitBranch,Info,Layers3,LockKeyhole,Search,ShieldCheck,Users} from 'lucide-react';
import catalog from './admin-catalog.json';
import './admin-control.css';
import './admin-preview.css';

const sections=[
 ['overview','Home',Layers3],
 ['users','Employees',Users],
 ['departments','Departments',Layers3],
 ['roles','Permissions',ShieldCheck],
 ['workflows','Document flows',GitBranch],
 ['audit','Activity',ClipboardList],
 ['storage','Advanced',Database],
];
const configuredConnections=catalog.filter(item=>item.next&&catalog.some(target=>target.name===item.next));
const groupNames=[...new Set(catalog.map(item=>item.group))].sort();
const lower=value=>String(value??'').toLowerCase();
const guides={
 users:{title:'Employees & logins',intro:'Invite employees, choose a department and assign the access they need.',steps:['Enter employee name and work email.','Choose their department and access role.','Send an invitation so they can set their password.']},
 departments:{title:'Departments',intro:'Create teams like Production, Quality, Stores, Sales or Purchase.',steps:['Add a department name and short code.','Save it to the company database.','Assign employees to that department.']},
 roles:{title:'Who can do what?',intro:'Decide which modules a job role can open and change.',steps:['Create a role, such as Stores Team.','Select the allowed actions for each module.','Save it, then assign the role to employees.']},
 audit:{title:'Recent admin activity',intro:'Keep a history of important management changes.',steps:['See who updated permissions or departments.','Review changes to workflow templates and employees.','Use the records when investigating issues.']},
 storage:{title:'Advanced database settings',intro:'Technical mapping between ERP data and the modules allowed to access it.',steps:['View existing data section mappings.','Change a mapping only if absolutely necessary.','Verify access after an authorized update.']},
};

function PreviewContent({onClose,publicMode}) {
 const [tab,setTab]=useState('overview');
 const [query,setQuery]=useState('');
 const [group,setGroup]=useState('All');
 const connections=useMemo(()=>configuredConnections.filter(item=>(group==='All'||item.group===group)&&(!query||lower(`${item.name} ${item.next} ${item.group}`).includes(lower(query)))),[group,query]);
 const isPublic=Boolean(publicMode);
 return <div className="admin-preview-screen">
  <header className="admin-preview-topbar">
   <div><strong>DFAB OneERP</strong><span>Admin Control Center</span></div>
   <button type="button" className="admin-button secondary" onClick={onClose}><ArrowLeft size={16}/> Back to sign in</button>
  </header>
  <main className="content page-shell admin-root admin-simple admin-preview-content">
   <div className="admin-title-row admin-simple-heading"><div><span className="admin-eyebrow">ADMINISTRATION · VIEW ONLY</span><h1>Manage your ERP</h1><p>See what each admin section does before you sign in.</p></div><span className="admin-preview-pill"><LockKeyhole size={15}/> Preview only</span></div>
   <div className="admin-preview-warning" role="status"><Info size={20}/><div><b>This is a simple, read-only guide.</b><p>{isPublic?'No company database information is exposed.':'This local preview uses built-in module definitions, not real employees or live Supabase data.'} To add staff, edit permissions or save changes, open the authenticated Admin Control Center.</p></div></div>
   <nav className="admin-tabs admin-simple-nav" aria-label="Admin preview sections">
    {sections.map(([key,title,Icon])=><button type="button" key={key} aria-current={tab===key?'page':undefined} className={tab===key?'active':''} onClick={()=>{setTab(key);setQuery('');setGroup('All')}}><Icon size={18}/><span>{title}</span></button>)}
   </nav>
   {tab==='overview'&&<>
    <div className="admin-overview-intro"><div><span className="admin-section-kicker">ADMIN HOME</span><h2>What do you want to manage?</h2><p>Open a section to see its purpose. Live data stays protected until sign-in.</p></div></div>
    <div className="admin-action-grid">{[
     ['users',Users,'Employees','Invite staff and change their access.'],
     ['departments',Layers3,'Departments','Organize teams and assign employees.'],
     ['roles',ShieldCheck,'Permissions','Control what each role can do.'],
     ['workflows',GitBranch,'Document flows','See how ERP documents connect.'],
     ['audit',ClipboardList,'Activity','Review administrator changes.'],
    ].map(([id,Icon,title,description])=><button key={id} type="button" className="admin-action-card" onClick={()=>setTab(id)}><span className="admin-action-icon"><Icon size={22}/></span><span className="admin-action-content"><b>{title}</b><small>{description}</small><em>View how it works</em></span><ArrowRight size={19}/></button>)}</div>
    <section className="admin-quick-guide"><div><h2>Recommended setup order</h2><p>For a new company ERP setup, follow these steps.</p></div><ol><li>Create <b>departments</b>.</li><li>Configure <b>permissions</b>.</li><li>Invite <b>employees</b>.</li></ol></section>
   </>}
   {tab==='workflows'&&<>
    <div className="admin-section-title"><div><span className="admin-section-kicker">DOCUMENT FLOW</span><h2>How ERP documents connect</h2><p>A document is created, reviewed and passed to the next stage only when its required checks pass.</p></div></div>
    {isPublic?<section className="admin-card"><h2>View the full connection map after sign-in</h2><p className="admin-preview-guide-text">Authenticated administrators can see the live ERP connection map, save a draft, and publish reviewed changes. No company workflow data is exposed here.</p><div className="admin-flow-row"><span className="flow-node">Source document</span><ArrowRight size={17}/><span className="flow-node destination">Next document</span></div></section>
     :<section className="admin-card"><div className="admin-card-heading"><div><h2>Built-in document connections</h2><p>These are from the application's static catalog, not confirmed published database connections.</p></div></div><div className="admin-tools"><label className="admin-search"><Search size={16}/><input aria-label="Search workflow" value={query} onChange={e=>setQuery(e.target.value)} placeholder="Find document"/></label><label className="admin-filter-label">Group<select value={group} onChange={e=>setGroup(e.target.value)}><option>All</option>{groupNames.map(name=><option key={name}>{name}</option>)}</select></label></div><div className="admin-flow-map">{connections.map(c=><div className="admin-flow-row" key={c.name}><span className="flow-node">{c.name}</span><ArrowRight size={17}/><span className="flow-node destination">{c.next}</span><small>{c.group}</small></div>)}{!connections.length&&<p className="admin-empty">No matching document flows.</p>}</div></section>}
   </>}
   {tab!=='overview'&&tab!=='workflows'&&<>
    <div className="admin-section-title"><div><span className="admin-section-kicker">ADMIN GUIDE</span><h2>{guides[tab].title}</h2><p>{guides[tab].intro}</p></div></div>
    <section className="admin-card admin-preview-guide-card"><h2>How this section works</h2><ol className="admin-preview-steps">{guides[tab].steps.map((step,i)=><li key={step}><span>{i+1}</span>{step}</li>)}</ol><div className="admin-preview-locked"><LockKeyhole size={24}/><b>Management actions are protected</b><p>This preview does not show real company records or permit edits. Sign in as an authorized administrator to use Add, Edit, Save and Delete.</p></div></section>
   </>}
   <div className="admin-preview-cta"><span><Check size={16}/> Your existing ERP data and workflows were not changed.</span><button className="admin-button" type="button" onClick={onClose}><ArrowRight size={16}/> Go to secure sign in</button></div>
  </main>
 </div>;
}

/** Signed-out view never loads Supabase data and never grants write access. */
export default function AdminPreview({onClose,publicMode=false}) {
 if(publicMode) return <PreviewContent onClose={onClose} publicMode/>;
 return <PreviewContent onClose={onClose} publicMode={false}/>;
}
