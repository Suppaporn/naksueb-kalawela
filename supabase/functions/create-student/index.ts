import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS'
};

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return Response.json({ error: 'Method not allowed' }, { status: 405, headers: corsHeaders });

  const projectUrl = Deno.env.get('SUPABASE_URL');
  const publishableKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!projectUrl || !publishableKey || !serviceRoleKey) {
    return Response.json({ error: 'Server configuration is incomplete' }, { status: 500, headers: corsHeaders });
  }

  const authorization = request.headers.get('Authorization');
  if (!authorization?.startsWith('Bearer ')) {
    return Response.json({ error: 'Sign in as a teacher first' }, { status: 401, headers: corsHeaders });
  }

  const caller = createClient(projectUrl, publishableKey, { global: { headers: { Authorization: authorization } } });
  const { data: { user }, error: authError } = await caller.auth.getUser();
  if (authError || !user) return Response.json({ error: 'Invalid session' }, { status: 401, headers: corsHeaders });

  const { data: teacher, error: teacherError } = await caller.from('profiles')
    .select('id,role').eq('id', user.id).maybeSingle();
  if (teacherError || teacher?.role !== 'teacher') {
    return Response.json({ error: 'Teacher access is required' }, { status: 403, headers: corsHeaders });
  }

  let payload: { studentCode?: string; displayName?: string; password?: string };
  try { payload = await request.json(); }
  catch { return Response.json({ error: 'Invalid request body' }, { status: 400, headers: corsHeaders }); }

  const studentCode = String(payload.studentCode || '').trim();
  const displayName = String(payload.displayName || '').trim();
  const password = String(payload.password || '');
  if (!/^[A-Za-z0-9_-]{1,24}$/.test(studentCode) || !displayName || displayName.length > 50 || password.length < 8 || password.length > 64) {
    return Response.json({ error: 'Use a 1–24 character student code, a display name, and a password of at least 8 characters.' }, { status: 400, headers: corsHeaders });
  }

  const admin = createClient(projectUrl, serviceRoleKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const email = `student-${studentCode.toLowerCase()}@students.naksueb.app`;
  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    app_metadata: { role: 'student' }
  });
  if (createError || !created.user) {
    return Response.json({ error: createError?.message || 'Unable to create the student account' }, { status: 409, headers: corsHeaders });
  }

  const { error: profileError } = await admin.from('profiles').insert({
    id: created.user.id,
    login_name: studentCode,
    display_name: displayName,
    role: 'student',
    teacher_id: teacher.id
  });
  if (profileError) {
    await admin.auth.admin.deleteUser(created.user.id);
    return Response.json({ error: profileError.message }, { status: 409, headers: corsHeaders });
  }

  return Response.json({ id: created.user.id, login_name: studentCode, display_name: displayName, role: 'student' }, { status: 201, headers: corsHeaders });
});
