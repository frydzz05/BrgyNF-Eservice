-- =====================================================================
--  v6 UPDATE  -  run ONCE in Supabase > SQL Editor (after supabase_update_v5.sql).
--  Safe to re-run.
--  * New document: "Pangkabuhayan" (FREE, NEW businesses only)
--  * Barangay Clearance is FREE for students
-- =====================================================================

create or replace function public.fee_for(p_doc_type text, p_details jsonb)
returns integer
language plpgsql
immutable
set search_path = public
as $$
declare
    purposes text[];
    p        text;
    n        int := 0;
    free_n   int := 0;
begin
    if p_doc_type = 'Pangkabuhayan' then
        return 0;                                   -- always free
    end if;

    if p_doc_type = 'Business Permit' then
        return case p_details ->> 'Group Code'
            when 'A'   then 100000      -- P1,000
            when 'B'   then 200000      -- P2,000
            when 'C'   then 300000      -- P3,000
            when 'D'   then 400000      -- P4,000
            when 'E'   then 500000      -- P5,000
            when 'NC'  then 200000      -- Business not otherwise categorized
            when 'REG' then 200000      -- Regulated business
            else null end;
    end if;

    -- Barangay Clearance: students are free
    if coalesce(p_details ->> 'Student', '') = 'Yes' then
        return 0;
    end if;

    -- P50, but FREE when every purpose ticked is Indigency / Medical / Financial
    purposes := string_to_array(coalesce(p_details ->> 'Purpose', ''), ',');
    foreach p in array purposes loop
        p := btrim(p);
        if p <> '' then
            n := n + 1;
            if p in ('Indigency', 'Medical', 'Financial') then free_n := free_n + 1; end if;
        end if;
    end loop;
    if n > 0 and n = free_n then return 0; end if;
    return 5000;                        -- P50
end $$;

create or replace function public.submit_application(p_name text, p_doc_type text, p_details jsonb)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
    yr         smallint;
    next_no    integer;
    new_serial text;
    amt        integer;
begin
    if p_doc_type not in ('Business Permit', 'Barangay Clearance', 'Pangkabuhayan') then
        raise exception 'Invalid document type';
    end if;
    if p_doc_type = 'Pangkabuhayan' and coalesce(p_details ->> 'Application Type', '') <> 'New' then
        raise exception 'Pangkabuhayan is only for NEW businesses';
    end if;

    amt := public.fee_for(p_doc_type, p_details);
    if amt is null then raise exception 'Please choose the business group'; end if;

    yr := (extract(year from (now() at time zone 'Asia/Manila'))::int % 100)::smallint;

    insert into serial_counters (year, last_no) values (yr, 1)
    on conflict (year) do update set last_no = serial_counters.last_no + 1
    returning last_no into next_no;

    new_serial := lpad(yr::text, 2, '0') || '-' ||
                  case when next_no < 10000 then lpad(next_no::text, 4, '0') else next_no::text end;

    insert into clearances (serial, name, document_type, details, amount_centavos, status, issued_at)
    values (new_serial, p_name, p_doc_type, p_details, amt,
            case when amt = 0 then 'paid' else 'pending' end,      -- free = nothing to pay
            case when amt = 0 then now() end);

    return new_serial;
end;
$$;
grant execute on function public.submit_application(text, text, jsonb) to anon, authenticated;
