-- Error: "Could not choose the best candidate function" al crear empresa.
-- Causa: quedaron DOS funciones crear_empresa (4 y 5 argumentos). PostgREST no sabe cuál usar.
-- Ejecutar UNA VEZ en Supabase → SQL Editor → Run (todo el archivo).

DROP FUNCTION IF EXISTS public.crear_empresa(text, text, date, text);

-- La buena es la de 5 argumentos; si al droppear la de 4 quedó intacta, no hace falta más.
-- Si por error borraste la de 5, vuelve a pegar supabase-paso-3-completo.sql (parte crear_empresa) o todo paso-3.

GRANT EXECUTE ON FUNCTION public.crear_empresa(text, text, date, text, text) TO authenticated;
