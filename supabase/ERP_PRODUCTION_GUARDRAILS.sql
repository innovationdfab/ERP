-- DFAB OneERP: additive production data-integrity guardrails.
-- IMPORTANT: apply ERP_FLOW_INTEGRITY_UPGRADE.sql first, test this on STAGING,
-- then schedule a coordinated frontend/backend deployment.
-- Does not modify application page layout, document values, or role assignments.
BEGIN;

-- A user can edit only while their organization and active ERP.EDIT role exist.
-- This applies even to SECURITY DEFINER RPCs which update compatibility state.
CREATE OR REPLACE FUNCTION public.erp_guard_ui_state_mutation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_org uuid;
BEGIN
  v_org := CASE WHEN TG_OP='DELETE' THEN OLD.organization_id ELSE NEW.organization_id END;
  IF auth.uid() IS NULL OR v_org IS DISTINCT FROM public.erp_current_org_id()
    OR NOT public.erp_has_permission('ERP.EDIT') THEN
    RAISE EXCEPTION 'ERP write access denied for this user and organization' USING ERRCODE='42501';
  END IF;
  RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END; $$;

DROP TRIGGER IF EXISTS trg_erp_ui_state_permissions ON public.erp_ui_state;
CREATE TRIGGER trg_erp_ui_state_permissions
BEFORE INSERT OR UPDATE OR DELETE ON public.erp_ui_state
FOR EACH ROW EXECUTE FUNCTION public.erp_guard_ui_state_mutation();

-- Compare-and-swap deletion is required to avoid deleting another employee's
-- newer section when the current page was based on an older snapshot.
CREATE OR REPLACE FUNCTION public.erp_delete_ui_state_if_unchanged(
  p_storage_key text, p_expected jsonb
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_org uuid := public.erp_current_org_id(); v_old jsonb;
BEGIN
  IF auth.uid() IS NULL OR v_org IS NULL OR NOT public.erp_has_permission('ERP.DELETE') THEN
    RAISE EXCEPTION 'ERP delete access denied' USING ERRCODE='42501';
  END IF;
  IF p_storage_key IS NULL OR p_storage_key !~ '^dfab-[a-zA-Z0-9 /_.-]+$' THEN
    RAISE EXCEPTION 'Invalid storage key';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(v_org::text || ':' || p_storage_key, 0));
  SELECT payload INTO v_old FROM public.erp_ui_state
  WHERE organization_id=v_org AND storage_key=p_storage_key FOR UPDATE;
  IF v_old IS DISTINCT FROM p_expected THEN
    RAISE EXCEPTION 'ERP records changed in another session. Reload before deleting.' USING ERRCODE='40001';
  END IF;
  DELETE FROM public.erp_ui_state WHERE organization_id=v_org AND storage_key=p_storage_key;
END; $$;

-- Existing trigger uses the first column of rows as a map key; repeated document
-- codes can otherwise overwrite previous rows in the derived erp_ui_records table.
-- Preserve all original values and their ordering, even with duplicate codes.
CREATE OR REPLACE FUNCTION public.erp_expand_ui_state()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE item jsonb; ord bigint; base_key text; rk text;
BEGIN
  DELETE FROM public.erp_ui_records
  WHERE organization_id=NEW.organization_id AND storage_key=NEW.storage_key;
  IF jsonb_typeof(NEW.payload)='array' THEN
    FOR item, ord IN SELECT value, ordinality
      FROM jsonb_array_elements(NEW.payload) WITH ORDINALITY LOOP
      base_key := COALESCE(NULLIF(item->>0,''),'__row_'||ord::text);
      rk := base_key;
      IF EXISTS(SELECT 1 FROM public.erp_ui_records
        WHERE organization_id=NEW.organization_id AND storage_key=NEW.storage_key AND record_key=rk) THEN
        rk := '__row_' || ord::text || '__' || base_key;
      END IF;
      INSERT INTO public.erp_ui_records(organization_id,storage_key,record_key,sort_order,payload)
      VALUES(NEW.organization_id,NEW.storage_key,rk,ord::int,item);
    END LOOP;
  ELSE
    INSERT INTO public.erp_ui_records(organization_id,storage_key,record_key,sort_order,payload)
    VALUES(NEW.organization_id,NEW.storage_key,'__singleton__',1,NEW.payload);
  END IF;
  RETURN NEW;
END; $$;

-- Keep the derived read model consistent when an entire UI section is deleted.
CREATE OR REPLACE FUNCTION public.erp_cleanup_ui_records()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  DELETE FROM public.erp_ui_records
   WHERE organization_id=OLD.organization_id AND storage_key=OLD.storage_key;
  RETURN OLD;
END; $$;
DROP TRIGGER IF EXISTS trg_erp_cleanup_ui_records ON public.erp_ui_state;
CREATE TRIGGER trg_erp_cleanup_ui_records
AFTER DELETE ON public.erp_ui_state FOR EACH ROW EXECUTE FUNCTION public.erp_cleanup_ui_records();

-- Immutable audit entry per document collection write. The previous and new
-- JSON can be large: for production retention, archive or partition audit rows.
DROP TRIGGER IF EXISTS trg_erp_ui_state_audit ON public.erp_ui_state;
CREATE TRIGGER trg_erp_ui_state_audit
AFTER INSERT OR UPDATE OR DELETE ON public.erp_ui_state
FOR EACH ROW EXECUTE FUNCTION public.erp_audit_trigger();

REVOKE ALL ON FUNCTION public.erp_delete_ui_state_if_unchanged(text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.erp_delete_ui_state_if_unchanged(text,jsonb) TO authenticated;

-- Frontend writes go through guarded RPC functions, not direct PostgREST DML.
REVOKE INSERT,UPDATE,DELETE ON public.erp_ui_state FROM authenticated;
REVOKE INSERT,UPDATE,DELETE ON public.erp_ui_records FROM authenticated;

COMMIT;
