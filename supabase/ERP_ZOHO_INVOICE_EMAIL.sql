-- Additive. Apply after ERP_PRODUCTION_PROCESS_CONTROLS.sql.
begin;
create table if not exists public.erp_invoice_email_jobs(
 organization_id uuid not null references public.erp_organizations(id),request_id uuid not null,
 actor_id uuid not null,invoice_no text not null,recipient text not null,
 status text not null check(status in ('processing','sent','failed','unknown')),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 primary key(organization_id,request_id));
alter table public.erp_invoice_email_jobs enable row level security;
revoke all on public.erp_invoice_email_jobs from public,anon,authenticated;
create or replace function public.erp_invoice_email_start(p_invoice text,p_to text,p_request uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_org uuid:=public.erp_current_org_id();v_doc jsonb;v_job public.erp_invoice_email_jobs%rowtype;
begin
 if auth.uid() is null or v_org is null or not public.erp_admin_can_page('Sales Invoice','view') or not public.erp_admin_can_page('Sales Invoice','export') then raise exception 'Invoice export permission required' using errcode='42501';end if;
 if p_to !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' or length(p_to)>254 then raise exception 'Valid recipient required';end if;
 perform pg_advisory_xact_lock(hashtextextended(v_org::text||p_request::text,0));
 select * into v_job from public.erp_invoice_email_jobs where organization_id=v_org and request_id=p_request;
 if found then
  if v_job.invoice_no<>p_invoice or v_job.recipient<>lower(p_to) then raise exception 'Email request identity changed';end if;
  return jsonb_build_object('created',false,'status',v_job.status);
 end if;
 select payload->p_invoice into v_doc from public.erp_ui_state where organization_id=v_org and storage_key='dfab-process-Sales Invoice';
 if v_doc is null or v_doc->>'status' not in ('APPROVED','RELEASED') or coalesce((v_doc->>'legacy')::boolean,false) then raise exception 'A saved and approved invoice with verified lines is required';end if;
 if (select count(*) from public.erp_invoice_email_jobs where organization_id=v_org and actor_id=auth.uid() and created_at>now()-interval '1 hour')>=30 then raise exception 'Email limit reached. Try later';end if;
 insert into public.erp_invoice_email_jobs values(v_org,p_request,auth.uid(),p_invoice,lower(p_to),'processing',now(),now());
 return jsonb_build_object('created',true,'status','processing','invoice',v_doc,'organization_id',v_org);
end; $$;
create or replace function public.erp_invoice_email_finish(p_request uuid,p_org uuid,p_status text)
returns void language plpgsql security definer set search_path=public as $$
begin
 if p_status not in ('sent','failed','unknown') then raise exception 'Invalid delivery state';end if;
 update public.erp_invoice_email_jobs set status=p_status,updated_at=now() where organization_id=p_org and request_id=p_request and status='processing';
end; $$;
revoke all on function public.erp_invoice_email_start(text,text,uuid),public.erp_invoice_email_finish(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.erp_invoice_email_start(text,text,uuid) to authenticated;
grant execute on function public.erp_invoice_email_finish(uuid,uuid,text) to service_role;
commit;
