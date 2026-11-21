# ตั้งค่าระบบบัญชีและความคืบหน้ากลาง

เว็บนี้ใช้ Supabase Auth และ Postgres เพื่อให้บัญชีผู้เรียนกับความคืบหน้าใช้ข้ามเครื่องได้ ส่วน GitHub Pages ยังโฮสต์ไฟล์หน้าเว็บแบบ static ต่อไป

## ค่าที่เปิดเผยได้

- `supabase-config.js` เก็บ Project URL และ Publishable key ซึ่งใช้ในเบราว์เซอร์ได้
- ห้ามใส่ `service_role`, Secret key หรือ Database password ในไฟล์เว็บหรือ GitHub
- ฟังก์ชันสร้างบัญชีใช้ `SUPABASE_SERVICE_ROLE_KEY` จากสภาพแวดล้อม Edge Function เท่านั้น

## เตรียมฐานข้อมูล

1. เปิด Supabase Dashboard ของโปรเจกต์ แล้วเข้า **SQL Editor**
2. เปิด `supabase/migrations/20261121000000_accounts_and_progress.sql` คัดลอกทั้งหมดไปวาง แล้วกด Run
3. Migration สร้าง `profiles`, `student_progress`, `student_state` และเปิด RLS พร้อม policies สำหรับให้นักเรียนอ่าน/แก้ข้อมูลตัวเอง และให้ครูดู/รีเซ็ตเฉพาะผู้เรียนที่ตนสร้าง

## สร้างบัญชีครูเริ่มต้น

1. ใน Dashboard เปิด **Authentication → Users → Add user**
2. สร้างผู้ใช้ด้วยอีเมลภายใน `krumhon@teachers.naksueb.app`, ตั้งรหัสผ่านครูที่แข็งแรง และยืนยันอีเมลให้แล้วเสร็จ ไม่ต้องใช้กล่องอีเมลจริง
3. ใน SQL Editor รันคำสั่งนี้เพื่อผูก Auth user เป็นครู (รหัสผ่านไม่เกี่ยวกับคำสั่งนี้):

```sql
insert into public.profiles (id, login_name, display_name, role)
select id, 'krumhon', 'ครูหมอน', 'teacher'
from auth.users
where lower(email) = 'krumhon@teachers.naksueb.app'
on conflict (id) do update
set login_name = excluded.login_name,
    display_name = excluded.display_name,
    role = excluded.role,
    teacher_id = null;
```

## Deploy Edge Function

สร้างฟังก์ชันชื่อ `create-student` ใน **Edge Functions** แล้ววาง source จาก `supabase/functions/create-student/index.ts` จากนั้น Deploy ฟังก์ชัน ค่า Supabase URL, anon key และ service role key ต้องมาจาก environment ของฟังก์ชัน ไม่ต้องใส่ใน source code

ฟังก์ชันตรวจ session และ role ครูก่อนสร้างบัญชี Auth กับ profile ผู้เรียน เมื่อสร้างจากหน้าครูแล้ว นักเรียนล็อกอินด้วยรหัสผู้เรียนและรหัสผ่านที่กำหนดได้จากทุกเครื่อง บัญชี Auth ภายในใช้ alias `student-<รหัส>@students.naksueb.app` โดยไม่ต้องมีอีเมลจริง

## เปิดตัวเกม

`supabase-config.js` มี Project URL และ Publishable key แล้ว หลังจากรัน migration, สร้าง profile ครู และ deploy Edge Function จึงเปิดใช้การล็อกอินออนไลน์ได้ ความคืบหน้าของหลักฐาน/กิจกรรมบันทึกใน `student_progress`; ด่านล่าสุดบันทึกใน `student_state`; แดชบอร์ดครูอ่านข้อมูลซ้ำทุก 12 วินาที

## ข้อจำกัด

- ห้ามใช้รหัสผ่านสาธิต `2026` เป็นรหัสจริงของครู เปลี่ยนเป็นรหัสผ่านใหม่ที่แข็งแรง
- บัญชีทั้งหมดเป็นข้อมูลของโปรเจกต์นี้; โปรดใช้ชื่อเล่นหรือรหัสผู้เรียนเท่าที่จำเป็น และอย่าใส่ข้อมูลส่วนตัวเกินความจำเป็น
- Supabase Free อาจพักโปรเจกต์ที่ไม่มีการใช้งานนานตามเงื่อนไขของแผน
