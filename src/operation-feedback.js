export function confirmedOperation(action,before,after){
 if(action==='delete'||Array.isArray(before)&&Array.isArray(after)&&after.length<before.length)return 'Deleted';
 if(action==='payment')return 'Payment saved';if(action==='close')return 'Closed';if(action==='handoff')return 'Draft created';if(action==='restore')return 'Restored';
 const entries=value=>value&&typeof value==='object'&&!Array.isArray(value)?Object.entries(value):[];
 const changed=entries(after).filter(([key,value])=>JSON.stringify(value)!==JSON.stringify(before?.[key]));
 const statuses=changed.map(([,v])=>v?.status).filter(Boolean);
 if(Array.isArray(after))for(const row of after){if(!Array.isArray(row))continue;const previous=Array.isArray(before)?before.find(r=>Array.isArray(r)&&r[0]===row[0]):null;for(let i=0;i<row.length;i++)if(typeof row[i]==='string'&&previous?.[i]!==row[i])statuses.push(row[i].toUpperCase());}
 if(action==='reject'||statuses.includes('REJECTED'))return 'Rejected';
 if(statuses.includes('DELIVERED'))return 'Delivery confirmed';if(statuses.includes('DISPATCHED'))return 'Dispatched';
 if(action==='approve'||statuses.some(s=>['APPROVED','PASSED','ACCEPTED'].includes(s)))return 'Approved';
 if(statuses.includes('APPROVAL PENDING'))return 'Submitted for approval';if(statuses.includes('RELEASED'))return 'Released';
 return 'Saved';
}
