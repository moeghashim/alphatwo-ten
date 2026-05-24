-- alphatwo-ten — platform schema (Sapiom/Blaxel + pluggable agent variant)
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- apps: one row per generated app
-- ---------------------------------------------------------------------------
do $$ begin
  create type app_status as enum (
    'queued', 'generating', 'building', 'pushing', 'deploying', 'live', 'failed'
  );
exception when duplicate_object then null; end $$;

create table if not exists apps (
  id                uuid primary key default gen_random_uuid(),
  slug              text not null unique,
  description       text not null,
  status            app_status not null default 'queued',
  status_message    text,
  tier              text not null default 'free',

  repo_url          text,
  repo_name         text,

  -- coding agent attempt metadata
  agent_used        text,                       -- cursor | claude | codex | gemini
  model_used        text,                       -- e.g. composer-2.5, gemini-3.5-flash
  fallback_used     boolean not null default false,
  attempt_count     int not null default 0,

  -- sandbox metadata (Sapiom / Blaxel)
  sandbox_id        text,
  sandbox_log_url   text,

  render_service_id text,
  render_deploy_id  text,

  preview_url       text,
  error             text,

  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  constraint apps_slug_format
    check (slug ~ '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$')
);

create index if not exists apps_status_idx     on apps(status);
create index if not exists apps_created_at_idx on apps(created_at desc);

-- ---------------------------------------------------------------------------
-- app_keys: scoped per-app bearer keys used by generated app's frontend
-- ---------------------------------------------------------------------------
create table if not exists app_keys (
  app_id     uuid not null references apps(id) on delete cascade,
  key_hash   text not null,
  created_at timestamptz not null default now(),
  primary key (app_id, key_hash)
);

-- ---------------------------------------------------------------------------
-- documents: shared multi-tenant JSON document store
-- ---------------------------------------------------------------------------
create table if not exists documents (
  app_id     uuid not null references apps(id) on delete cascade,
  collection text not null,
  doc_id     text not null,
  body       jsonb not null,
  deleted_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (app_id, collection, doc_id),
  constraint documents_collection_format
    check (collection ~ '^[a-z0-9][a-z0-9_-]{0,62}$')
);

create index if not exists documents_list_idx
  on documents(app_id, collection, updated_at desc)
  where deleted_at is null;

-- Row-Level Security (defense in depth — API also enforces app scope)
alter table documents enable row level security;

drop policy if exists documents_tenant_isolation on documents;
create policy documents_tenant_isolation on documents
  using (app_id = current_setting('app.current_id', true)::uuid)
  with check (app_id = current_setting('app.current_id', true)::uuid);

-- ---------------------------------------------------------------------------
-- updated_at trigger
-- ---------------------------------------------------------------------------
create or replace function set_updated_at() returns trigger as $$
begin new.updated_at = now(); return new; end;
$$ language plpgsql;

drop trigger if exists apps_updated_at on apps;
create trigger apps_updated_at before update on apps
  for each row execute function set_updated_at();

drop trigger if exists documents_updated_at on documents;
create trigger documents_updated_at before update on documents
  for each row execute function set_updated_at();
