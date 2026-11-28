-- Teacher reviewed guide answers. Existing installations should run this migration
-- after 20261121000000_accounts_and_progress.sql.
create table if not exists public.guide_question_bank (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references public.profiles(id) on delete cascade,
  stage_id text not null check (stage_id in ('oldstone', 'middlestone', 'neolithic', 'bronze', 'iron')),
  question text not null check (length(btrim(question)) between 1 and 160),
  normalized_question text not null check (length(normalized_question) between 1 and 320),
  status text not null default 'pending' check (status in ('pending', 'answered')),
  answer text,
  asked_by_student_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  answered_at timestamptz,
  answered_by uuid references public.profiles(id) on delete set null,
  constraint guide_question_bank_teacher_question_unique unique (teacher_id, stage_id, normalized_question),
  constraint guide_question_bank_answer_state check (
    (status = 'pending' and answer is null and answered_at is null and answered_by is null)
    or
    (status = 'answered' and length(btrim(answer)) between 1 and 1200 and answered_at is not null and answered_by is not null)
  )
);

create index if not exists guide_question_bank_teacher_pending_idx
  on public.guide_question_bank (teacher_id, status, created_at desc);

alter table public.guide_question_bank enable row level security;

drop policy if exists guide_question_bank_read_for_teacher_or_student on public.guide_question_bank;
create policy guide_question_bank_read_for_teacher_or_student
  on public.guide_question_bank for select to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'teacher' and p.id = guide_question_bank.teacher_id
    )
    or
    (
      status = 'answered'
      and exists (
        select 1 from public.profiles p
        where p.id = auth.uid() and p.role = 'student'
          and p.teacher_id = guide_question_bank.teacher_id
      )
    )
  );

drop policy if exists guide_question_bank_student_submit on public.guide_question_bank;
create policy guide_question_bank_student_submit
  on public.guide_question_bank for insert to authenticated
  with check (
    status = 'pending' and answer is null and answered_at is null and answered_by is null
    and asked_by_student_id = auth.uid()
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'student' and p.teacher_id = guide_question_bank.teacher_id
    )
  );

drop policy if exists guide_question_bank_teacher_answer on public.guide_question_bank;
create policy guide_question_bank_teacher_answer
  on public.guide_question_bank for update to authenticated
  using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'teacher' and p.id = guide_question_bank.teacher_id
    )
  )
  with check (
    teacher_id = auth.uid() and status = 'answered' and answered_by = auth.uid()
    and answer is not null and answered_at is not null
  );

grant select, insert, update on public.guide_question_bank to authenticated;
