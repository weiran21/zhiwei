-- ============================================================
-- 知微工作台 · 自定义头像 Supabase 建表脚本
-- 在 Supabase 控制台 → SQL Editor 粘贴执行一次即可。
-- 作用：① 建公开存储桶 user_avatar；② 存储读写策略（读公开 / 写仅本人）；
--      ③ 建 profiles 用户资料表（id=auth.users.id，avatar_url）；④ 行级安全 RLS；
--      ⑤ 注册触发器：新用户自动建一行 profile。
-- ============================================================

-- ---------- 1. 存储桶 ----------
-- 公开桶（avatar 可被任意端直接访问，不敏感）
insert into storage.buckets (id, name, public)
values ('user_avatar', 'user_avatar', true)
on conflict (id) do nothing;

-- ---------- 2. 存储对象读写策略 ----------
-- 2.1 公开读：任何人都能 GET 头像
drop policy if exists "avatar_public_read" on storage.objects;
create policy "avatar_public_read" on storage.objects
  for select using (bucket_id = 'user_avatar');

-- 2.2 仅本人可上传 / 更新 / 删除
--    文件名约定：{user_id}_avatar.webp，按首个下划线前的片段鉴权
drop policy if exists "avatar_owner_write" on storage.objects;
create policy "avatar_owner_write" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'user_avatar'
    and split_part(name, '_', 1) = auth.uid()::text
  );

drop policy if exists "avatar_owner_update" on storage.objects;
create policy "avatar_owner_update" on storage.objects
  for update to authenticated using (
    bucket_id = 'user_avatar'
    and split_part(name, '_', 1) = auth.uid()::text
  );

drop policy if exists "avatar_owner_delete" on storage.objects;
create policy "avatar_owner_delete" on storage.objects
  for delete to authenticated using (
    bucket_id = 'user_avatar'
    and split_part(name, '_', 1) = auth.uid()::text
  );

-- ---------- 3. profiles 用户资料表 ----------
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  avatar_url  text,
  updated_at  timestamptz not null default now()
);

-- ---------- 4. profiles 行级安全 ----------
alter table public.profiles enable row level security;

-- 自己可读
drop policy if exists "profiles_self_select" on public.profiles;
create policy "profiles_self_select" on public.profiles
  for select using (auth.uid() = id);

-- 自己可插入（注册触发器建行 / upsert）
drop policy if exists "profiles_self_insert" on public.profiles;
create policy "profiles_self_insert" on public.profiles
  for insert with check (auth.uid() = id);

-- 自己可更新（改头像）
drop policy if exists "profiles_self_update" on public.profiles;
create policy "profiles_self_update" on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

-- 允许匿名/已认证读取别人的头像（头像需多端可访问）
-- 上面 profiles_self_select 只允许自己读；这里追加公开读策略
drop policy if exists "profiles_public_select" on public.profiles;
create policy "profiles_public_select" on public.profiles
  for select using (true);

-- ---------- 5. 注册触发器：新用户自动建 profile ----------
create or replace function public.handle_new_profile()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id) values (new.id) on conflict do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_profile();
