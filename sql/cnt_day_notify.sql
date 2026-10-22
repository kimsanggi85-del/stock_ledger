-- 매월 말일(한국시간) 오전 8시, ntfy 'tajincall' 로 '재고실사 날입니다' 1회 발송
-- (Supabase 에 적용됨: 함수 public.cnt_day_notify + pg_cron 작업 'cnt-day-notify')
-- 발송 기록: kv_store 'tj_cnt_ntfy_v1' = {"YYYY-MM": 보낸시각} — 같은 달은 다시 보내지 않는다
-- 점검(발송 안 함): select public.cnt_day_notify(true);
create or replace function public.cnt_day_notify(p_dry boolean default false)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  d    date := (now() at time zone 'Asia/Seoul')::date;
  ym   text := to_char(d, 'YYYY-MM');
  last boolean := (d + 1) = date_trunc('month', d + 1)::date;   -- 내일이 1일이면 오늘이 말일
  sent jsonb;
  body jsonb;
begin
  if not last then return jsonb_build_object('send', false, 'why', 'not month end', 'date', d); end if;
  select value into sent from kv_store where key = 'tj_cnt_ntfy_v1';
  if sent ? ym then return jsonb_build_object('send', false, 'why', 'already sent', 'ym', ym); end if;
  body := jsonb_build_object(
    'topic', 'tajincall',
    'title', to_char(d, 'FMMM') || '월 월마감 재고실사',
    'message', '재고실사 날입니다',
    'tags', jsonb_build_array('clipboard'),
    'priority', 4,
    'click', 'https://kimsanggi85-del.github.io/stock_ledger/');
  if p_dry then return jsonb_build_object('send', true, 'dry', true, 'body', body); end if;
  perform net.http_post(url := 'https://ntfy.sh/', body := body,
    headers := '{"Content-Type":"application/json"}'::jsonb, timeout_milliseconds := 15000);
  insert into kv_store(key, value, updated_at)
    values ('tj_cnt_ntfy_v1', jsonb_build_object(ym, now()), now())
    on conflict (key) do update set value = coalesce(kv_store.value, '{}'::jsonb) || jsonb_build_object(ym, now()), updated_at = now();
  return jsonb_build_object('send', true, 'ym', ym);
end $$;

-- 08:00 KST = 23:00 UTC 전날. 말일 후보(27~30일 UTC)에만 돌고 함수가 말일인지 확인한다
select cron.schedule('cnt-day-notify', '0 23 27-30 * *', $$select public.cnt_day_notify(false);$$);
