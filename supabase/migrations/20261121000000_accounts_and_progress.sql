create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  login_name text not null,
  display_name text not null,
  role text not null check (role in ('teacher', 'student')),
  teacher_id uuid references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint student_teacher_role check ((role = 'teacher' and teacher_id is null) or (role = 'student' and teacher_id is not null))
);

create unique index if not exists profiles_login_name_lower_unique on public.profiles (lower(login_name));
create index if not exists profiles_teacher_id_idx on public.profiles (teacher_id) where role = 'student';

create table if not exists public.student_progress (
  student_id uuid not null references public.profiles (id) on delete cascade,
  stage_id text not null check (stage_id in ('oldstone', 'middlestone', 'neolithic', 'bronze', 'iron')),
  found_evidence text[] not null default '{}',
  activity_count integer not null default 0 check (activity_count between 0 and 5),
  passed boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (student_id, stage_id)
);

create table if not exists public.student_state (
  student_id uuid primary key references public.profiles (id) on delete cascade,
  active_stage_id text not null default 'oldstone' check (active_stage_id in ('oldstone', 'middlestone', 'neolithic', 'bronze', 'iron')),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.student_progress enable row level security;
alter table public.student_state enable row level security;

drop policy if exists profiles_select_self_or_students_in_class on public.profiles;
create policy profiles_select_self_or_students_in_class on public.profiles
  for select to authenticated
  using (id = auth.uid() or (role = 'student' and teacher_id = auth.uid()));

drop policy if exists progress_select_self_or_teacher on public.student_progress;
create policy progress_select_self_or_teacher on public.student_progress
  for select to authenticated
  using (
    student_id = auth.uid()
    or exists (
      select 1 from public.profiles p
      where p.id = student_progress.student_id and p.role = 'student' and p.teacher_id = auth.uid()
    )
  );

drop policy if exists progress_insert_self_or_teacher on public.student_progress;
create policy progress_insert_self_or_teacher on public.student_progress
  for insert to authenticated
  with check (
    student_id = auth.uid()
    or exists (
      select 1 from public.profiles p
      where p.id = student_progress.student_id and p.role = 'student' and p.teacher_id = auth.uid()
    )
  );

drop policy if exists progress_update_self_or_teacher on public.student_progress;
create policy progress_update_self_or_teacher on public.student_progress
  for update to authenticated
  using (
    student_id = auth.uid()
    or exists (
      select 1 from public.profiles p
      where p.id = student_progress.student_id and p.role = 'student' and p.teacher_id = auth.uid()
    )
  )
  with check (
    student_id = auth.uid()
    or exists (
      select 1 from public.profiles p
      where p.id = student_progress.student_id and p.role = 'student' and p.teacher_id = auth.uid()
    )
  );

drop policy if exists state_select_self_or_teacher on public.student_state;
create policy state_select_self_or_teacher on public.student_state
  for select to authenticated
  using (
    student_id = auth.uid()
    or exists (
      select 1 from public.profiles p
      where p.id = student_state.student_id and p.role = 'student' and p.teacher_id = auth.uid()
    )
  );

drop policy if exists state_insert_self on public.student_state;
create policy state_insert_self on public.student_state
  for insert to authenticated
  with check (student_id = auth.uid());

drop policy if exists state_update_self on public.student_state;
create policy state_update_self on public.student_state
  for update to authenticated
  using (student_id = auth.uid())
  with check (student_id = auth.uid());

drop policy if exists state_delete_teacher on public.student_state;
create policy state_delete_teacher on public.student_state
  for delete to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = student_state.student_id and p.role = 'student' and p.teacher_id = auth.uid()
    )
  );

grant usage on schema public to authenticated;
grant select on public.profiles to authenticated;
grant select, insert, update on public.student_progress to authenticated;
grant select, insert, update, delete on public.student_state to authenticated;

-- The create-student Edge Function uses the service role to create the Auth
-- user and its profile. Keep its table access explicit for reproducible setup.
grant usage on schema public to service_role;
grant select, insert, update, delete on public.profiles to service_role;

