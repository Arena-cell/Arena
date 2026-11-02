-- LOCAL DRAFT ONLY. Requires explicit approval before hosted deployment.
begin;
create table public.arena_governorates(code text primary key,name_ar text not null,name_en text not null);
create table public.arena_wilayats(governorate_code text not null references public.arena_governorates(code),code text not null,name_ar text not null,name_en text not null,primary key(governorate_code,code));
alter table public.arena_governorates enable row level security;
alter table public.arena_wilayats enable row level security;
revoke all on public.arena_governorates,public.arena_wilayats from public,anon,authenticated;
grant select on public.arena_governorates,public.arena_wilayats to anon,authenticated;
create policy geography_read on public.arena_governorates for select to anon,authenticated using(true);
create policy geography_read on public.arena_wilayats for select to anon,authenticated using(true);
insert into public.arena_governorates values
('muscat','مسقط','Muscat'),
('dhofar','ظفار','Dhofar'),
('musandam','مسندم','Musandam'),
('buraimi','البريمي','Al Buraimi'),
('dakhiliyah','الداخلية','Ad Dakhiliyah'),
('north_batinah','شمال الباطنة','North Al Batinah'),
('south_batinah','جنوب الباطنة','South Al Batinah'),
('south_sharqiyah','جنوب الشرقية','South Ash Sharqiyah'),
('north_sharqiyah','شمال الشرقية','North Ash Sharqiyah'),
('dhahirah','الظاهرة','Ad Dhahirah'),
('wusta','الوسطى','Al Wusta');
insert into public.arena_wilayats values
('muscat','muscat','مسقط','Muscat'),
('muscat','muttrah','مطرح','Muttrah'),
('muscat','amerat','العامرات','Al Amerat'),
('muscat','bousher','بوشر','Bousher'),
('muscat','seeb','السيب','Seeb'),
('muscat','quriyat','قريات','Quriyat'),
('dhofar','salalah','صلالة','Salalah'),
('dhofar','taqah','طاقة','Taqah'),
('dhofar','mirbat','مرباط','Mirbat'),
('dhofar','rakhyut','رخيوت','Rakhyut'),
('dhofar','thumrait','ثمريت','Thumrait'),
('dhofar','dhalkut','ضلكوت','Dhalkut'),
('dhofar','mazyona','المزيونة','Al Mazyona'),
('dhofar','muqshin','مقشن','Muqshin'),
('dhofar','shalim','شليم وجزر الحلانيات','Shalim and Hallaniyat Islands'),
('dhofar','sadah','سدح','Sadah'),
('musandam','khasab','خصب','Khasab'),
('musandam','dibba','دبا','Dibba'),
('musandam','bukha','بخاء','Bukha'),
('musandam','madha','مدحاء','Madha'),
('buraimi','buraimi','البريمي','Al Buraimi'),
('buraimi','mahdah','محضة','Mahdah'),
('buraimi','sunaynah','السنينة','Al Sunaynah'),
('dakhiliyah','nizwa','نزوى','Nizwa'),
('dakhiliyah','bahla','بهلاء','Bahla'),
('dakhiliyah','manah','منح','Manah'),
('dakhiliyah','hamra','الحمراء','Al Hamra'),
('dakhiliyah','adam','أدم','Adam'),
('dakhiliyah','izki','إزكي','Izki'),
('dakhiliyah','samail','سمائل','Samail'),
('dakhiliyah','bidbid','بدبد','Bidbid'),
('dakhiliyah','jabal_akhdar','الجبل الأخضر','Al Jabal Al Akhdar'),
('north_batinah','sohar','صحار','Sohar'),
('north_batinah','shinas','شناص','Shinas'),
('north_batinah','liwa','لوى','Liwa'),
('north_batinah','saham','صحم','Saham'),
('north_batinah','khaburah','الخابورة','Al Khaburah'),
('north_batinah','suwayq','السويق','Al Suwayq'),
('south_batinah','rustaq','الرستاق','Rustaq'),
('south_batinah','awabi','العوابي','Al Awabi'),
('south_batinah','nakhal','نخل','Nakhal'),
('south_batinah','wadi_maawil','وادي المعاول','Wadi Al Maawil'),
('south_batinah','barka','بركاء','Barka'),
('south_batinah','musannah','المصنعة','Al Musannah'),
('south_sharqiyah','sur','صور','Sur'),
('south_sharqiyah','kamil_wafi','الكامل والوافي','Al Kamil and Al Wafi'),
('south_sharqiyah','jalan_bu_hassan','جعلان بني بو حسن','Jalan Bani Bu Hassan'),
('south_sharqiyah','jalan_bu_ali','جعلان بني بو علي','Jalan Bani Bu Ali'),
('south_sharqiyah','masirah','مصيرة','Masirah'),
('north_sharqiyah','ibra','إبراء','Ibra'),
('north_sharqiyah','mudhaibi','المضيبي','Al Mudhaibi'),
('north_sharqiyah','bidiyah','بدية','Bidiyah'),
('north_sharqiyah','qabil','القابل','Al Qabil'),
('north_sharqiyah','wadi_bani_khalid','وادي بني خالد','Wadi Bani Khalid'),
('north_sharqiyah','dima_tayyin','دماء والطائيين','Dima and Al Tayyin'),
('north_sharqiyah','sinaw','سناو','Sinaw'),
('dhahirah','ibri','عبري','Ibri'),
('dhahirah','yanqul','ينقل','Yanqul'),
('dhahirah','dhank','ضنك','Dhank'),
('wusta','haima','هيماء','Haima'),
('wusta','mahout','محوت','Mahout'),
('wusta','duqm','الدقم','Duqm'),
('wusta','jazer','الجازر','Al Jazer');
alter table public.arenas add column if not exists governorate_code text;
alter table public.arenas add column if not exists wilayat_code text;
alter table public.arenas add column if not exists contact_phone text;
alter table public.arenas add column if not exists editor_draft boolean not null default false;
alter table public.arenas add column if not exists location_status text not null default 'legacy';
alter table public.arenas add constraint arena_region_pair check((governorate_code is null)=(wilayat_code is null));
alter table public.arenas add constraint arena_region_reference foreign key(governorate_code,wilayat_code) references public.arena_wilayats(governorate_code,code);
alter table public.arenas add constraint arena_contact_phone_format check(contact_phone is null or contact_phone~'^\+968[279][0-9]{7}$');
alter table public.arenas add constraint arena_location_status check(location_status in('legacy','explicit_pin','existing_coordinates','unresolved'));

create function arena_private.normalize_oman_contact(p text) returns text language plpgsql immutable set search_path=pg_catalog as $$
declare n text;begin
 if nullif(trim(p),'') is null then return null;end if;
 n:=regexp_replace(translate(trim(p),'٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹','01234567890123456789'),'[[:space:]()-]','','g');
 n:=regexp_replace(n,'^00','+');n:=regexp_replace(n,'^\+?968','');
 if n!~'^[279][0-9]{7}$' then raise exception 'INVALID_OMAN_CONTACT' using errcode='22023';end if;
 return '+968'||n;
end $$;
create function arena_private.google_maps_pin(p text) returns jsonb language plpgsql immutable set search_path=pg_catalog as $$
declare a text[];lat numeric;lng numeric;begin
 if p is null then return null;end if;
 if p!~'^https://((www\.)?google\.com/maps([/?]|$)|maps\.google\.com([/?]|$)|maps\.app\.goo\.gl/|goo\.gl/maps/)' then raise exception 'INVALID_GOOGLE_MAPS_URL' using errcode='22023';end if;
 if (select count(*) from regexp_matches(p,'!3d(-?[0-9]+(?:\.[0-9]+)?)!4d(-?[0-9]+(?:\.[0-9]+)?)','g'))>1 then return null;end if;
 a:=regexp_match(p,'!3d(-?[0-9]+(?:\.[0-9]+)?)!4d(-?[0-9]+(?:\.[0-9]+)?)');
 if a is null then
  a:=regexp_match(p,'[?&](?:query|q|destination)=(-?[0-9]+(?:\.[0-9]+)?)(?:,|%2[Cc])(?:\s|%20)*(-?[0-9]+(?:\.[0-9]+)?)(?:&|$)');
 end if;
 if a is null then return null;end if;
 lat:=a[1]::numeric;lng:=a[2]::numeric;
 if abs(lat)>90 or abs(lng)>180 then raise exception 'INVALID_MAP_COORDINATES' using errcode='22023';end if;
 return jsonb_build_object('latitude',lat,'longitude',lng);
end $$;
revoke all on function arena_private.normalize_oman_contact(text),arena_private.google_maps_pin(text) from public,anon,authenticated;

create function public.validate_arena_editor_metadata() returns trigger language plpgsql security definer set search_path=pg_catalog,public,arena_private as $$
declare pin jsonb;g public.arena_governorates%rowtype;w public.arena_wilayats%rowtype;begin
 new.contact_phone:=arena_private.normalize_oman_contact(new.contact_phone);
 if tg_op='INSERT' or new.google_maps_url is distinct from old.google_maps_url then
  new.google_maps_url:=nullif(trim(new.google_maps_url),'');
  pin:=arena_private.google_maps_pin(new.google_maps_url);
  if pin is not null then new.latitude:=(pin->>'latitude')::double precision;new.longitude:=(pin->>'longitude')::double precision;new.location_status:='explicit_pin';
  elsif new.latitude is not null and new.longitude is not null then new.location_status:='existing_coordinates';
  else new.location_status:='unresolved';end if;
 end if;
 if new.governorate_code is not null and new.wilayat_code is not null then
  select * into strict g from public.arena_governorates where code=new.governorate_code;
  select * into strict w from public.arena_wilayats where governorate_code=new.governorate_code and code=new.wilayat_code;
  new.location_ar:=concat_ws('، ',g.name_ar,w.name_ar,nullif(trim(new.area_ar),''));
  new.location_en:=concat_ws(', ',g.name_en,w.name_en,coalesce(nullif(trim(new.area_en),''),nullif(trim(new.area_ar),'')));
  new.location:=new.location_en;
 end if;
 return new;
end $$;
revoke all on function public.validate_arena_editor_metadata() from public,anon,authenticated;
create trigger arena_editor_metadata before insert or update of google_maps_url,contact_phone,governorate_code,wilayat_code,area_ar,area_en on public.arenas for each row execute function public.validate_arena_editor_metadata();

create function public.save_arena_editor(p_arena uuid,p_details jsonb) returns uuid language plpgsql security invoker set search_path=pg_catalog,public as $$
declare row public.arenas%rowtype;exists_row boolean;urls text[];url text;object_name text;draft boolean;begin
 if auth.uid() is null or p_arena is null or jsonb_typeof(p_details)<>'object' then raise exception 'NOT_AUTHORIZED' using errcode='42501';end if;
 select * into row from public.arenas where id=p_arena for update;exists_row:=found;
 if (exists_row and not public.is_arena_operator(p_arena)) or (not exists_row and not public.is_platform_admin()) then raise exception 'NOT_AUTHORIZED' using errcode='42501';end if;
 if not exists_row and (nullif(p_details->>'governorate_code','') is null or nullif(p_details->>'wilayat_code','') is null or nullif(p_details->>'contact_phone','') is null) then raise exception 'REGION_AND_CONTACT_REQUIRED';end if;
 if nullif(trim(p_details->>'name_ar'),'') is null or nullif(trim(p_details->>'name_en'),'') is null then raise exception 'ARENA_NAME_REQUIRED';end if;
 if jsonb_typeof(p_details->'image_urls') is distinct from 'array' then raise exception 'IMAGE_LIST_REQUIRED';end if;
 select coalesce(array_agg(value order by ord),'{}') into urls from jsonb_array_elements_text(p_details->'image_urls') with ordinality x(value,ord);
 foreach url in array urls loop
  if exists_row and url=any(coalesce(row.image_urls,'{}')) then continue;end if;
  if url not like 'https://gtcrijikfaglqcwqozel.supabase.co/storage/v1/object/public/stadium-images/%' then raise exception 'VALIDATED_ARENA_IMAGE_REQUIRED' using errcode='42501';end if;
  object_name:=substr(url,length('https://gtcrijikfaglqcwqozel.supabase.co/storage/v1/object/public/stadium-images/')+1);
  if split_part(object_name,'/',2)<>p_arena::text or not exists(select 1 from storage.objects where bucket_id='stadium-images' and name=object_name) then raise exception 'VALIDATED_ARENA_IMAGE_REQUIRED' using errcode='42501';end if;
 end loop;
 draft:=coalesce((p_details->>'editor_draft')::boolean,false);
 if not exists_row then
  insert into public.arenas(id,name,name_ar,name_en,location,price_per_hour,court_count,audience_gender,sports,is_active,editor_draft)
  values(p_arena,trim(p_details->>'name_en'),trim(p_details->>'name_ar'),trim(p_details->>'name_en'),'Pending location',(p_details->>'price_per_hour')::numeric,(p_details->>'court_count')::integer,p_details->>'audience_gender',array(select jsonb_array_elements_text(p_details->'sports')),not draft,draft);
 end if;
 update public.arenas set name=trim(p_details->>'name_en'),name_ar=trim(p_details->>'name_ar'),name_en=trim(p_details->>'name_en'),
 description_ar=nullif(p_details->>'description_ar',''),description_en=nullif(p_details->>'description_en',''),description=coalesce(nullif(p_details->>'description_en',''),nullif(p_details->>'description_ar','')),
 governorate_code=nullif(p_details->>'governorate_code',''),wilayat_code=nullif(p_details->>'wilayat_code',''),area_ar=nullif(p_details->>'area_ar',''),area_en=nullif(p_details->>'area_en',''),
 address_ar=nullif(p_details->>'address_ar',''),address_en=nullif(p_details->>'address_en',''),google_maps_url=nullif(p_details->>'google_maps_url',''),contact_phone=nullif(p_details->>'contact_phone',''),
 price_per_hour=(p_details->>'price_per_hour')::numeric,court_count=(p_details->>'court_count')::integer,audience_gender=p_details->>'audience_gender',
 sports=array(select jsonb_array_elements_text(p_details->'sports')),opening_time=nullif(p_details->>'opening_time','')::time,closing_time=nullif(p_details->>'closing_time','')::time,image_urls=urls,
 editor_draft=draft,is_active=case when (not exists_row or row.editor_draft) and not draft then true else is_active end
 where id=p_arena;
 return p_arena;
end $$;
revoke all on function public.save_arena_editor(uuid,jsonb) from public,anon;
grant execute on function public.save_arena_editor(uuid,jsonb) to authenticated;
commit;
