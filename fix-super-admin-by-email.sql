-- ============================================================
-- Dar rol super_admin a tu cuenta (ejecutar en Supabase → SQL Editor)
-- 1) Cambia el correo abajo por el MISMO que usas en "Ingresar" del panel.
-- 2) Run. Luego recarga super-admin.html e inicia sesión otra vez.
-- ============================================================

-- A) Ver que el usuario existe en Auth (debe salir 1 fila)
SELECT id, email, email_confirmed_at, created_at
FROM auth.users
WHERE lower(trim(email)) = lower(trim('TU_CORREO@gmail.com'));

-- B) Asignar / actualizar perfil como super_admin (enum app_role)
INSERT INTO public.profiles (id, role)
SELECT id, 'super_admin'::public.app_role
FROM auth.users
WHERE lower(trim(email)) = lower(trim('TU_CORREO@gmail.com'))
ON CONFLICT (id) DO UPDATE
SET role = 'super_admin'::public.app_role;

-- C) Comprobar resultado
SELECT p.id, u.email, p.role::text AS role, p.empresa_id
FROM public.profiles p
JOIN auth.users u ON u.id = p.id
WHERE lower(trim(u.email)) = lower(trim('TU_CORREO@gmail.com'));

-- Debe mostrar role = super_admin. Si (B) insertó 0 filas, el correo no coincide con auth.users
-- (typo, otro proveedor OAuth, o usuario creado en otro proyecto Supabase).
