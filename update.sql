-- Dilo Perdi: no duplicate reports within 25 metres.
-- Paste everything into Supabase > SQL Editor and press Run. Safe to run more than once.

create or replace function public.submit_report(
  p_id uuid, p_lat double precision, p_lon double precision,
  p_sev text, p_note text, p_photo_path text, p_device text
) returns text
language plpgsql security definer set search_path = public
as $$
declare dup record;
begin
  -- Is there already a leak (waiting or on the map) within 25 metres?
  select id, status into dup from public.reports
   where status in ('pending','approved')
     and lat between p_lat - 0.0005 and p_lat + 0.0005
     and lon between p_lon - 0.0005 and p_lon + 0.0005
     and sqrt(power((lat - p_lat) * 111320, 2) + power((lon - p_lon) * 104400, 2)) < 25
   order by created_at
   limit 1;

  if found then
    -- Count the new visit as a "still leaking" confirmation.
    if dup.status = 'approved' then
      update public.reports
         set last_seen_at = now(), confirms = confirms + 1
       where id = dup.id and last_seen_at < now() - interval '1 hour';
    end if;
    return 'duplicate';
  end if;

  insert into public.reports (id, lat, lon, sev, note, photo_path, device)
  values (p_id, p_lat, p_lon, p_sev, p_note, p_photo_path, p_device);
  return 'created';
end
$$;

revoke all on function public.submit_report(uuid, double precision, double precision, text, text, text, text) from public;
grant execute on function public.submit_report(uuid, double precision, double precision, text, text, text, text) to anon, authenticated;

-- From now on new reports come only through submit_report.
drop policy if exists "anyone can report" on public.reports;
revoke insert on public.reports from anon, authenticated;
