# SimNeuro v3 — ingreso y autenticación (estilo simulador de innovación)

## Pasos (una sola vez)
1. Supabase → SQL Editor → pegar TODO `schema_v2.sql` → Run. (Borra las tablas de la versión anterior; no había datos reales.)
2. En el mismo editor, ejecutar estas dos líneas con TUS datos (una a la vez):
   select public.sn_crear_clase('UAB Mercadeo Estratégico 2026','TU-CODIGO-DE-CLASE');   -- código ≥ 8 caracteres; no distingue mayúsculas (la pantalla lo muestra en MAYÚSCULAS)
   select public.sn_crear_docente('Jhonny Atila','tu-correo@ejemplo.com','CLAVE-TEMPORAL-8+','Tu pregunta secreta (≥8 car.)','tu respuesta');
3. GitHub → repositorio → reemplazar `index.html` por el de esta carpeta (Add file → Upload files → Commit).
4. Docente: abrir la página → Docente → ingresar con tu correo y la clave temporal → te pedirá una nueva (≥ 8).

## Cómo ingresan (misma pantalla que el simulador de innovación)
- Una sola pantalla de acceso: campo «Nombre de equipo · Correo del profesor» + contraseña; el código de clase se pide solo a los equipos.
- Botones: ¿Olvidaste tu contraseña? (docentes), Registrar mi equipo, Ver Manual.

## Estudiantes
- Un integrante: "Registrar mi equipo" (código de clase, nombre del equipo, producto, contraseña, alias de los integrantes).
- Los demás: "Ingresar" (código, nombre del equipo, contraseña) y eligen su alias.
- Solo alias, nunca nombres reales.

## Seguridad
- 5 intentos fallidos → bloqueo de 15 min por equipo/correo. Docente → Equipos registrados → "Reiniciar clave" da una clave temporal de 6 caracteres que el equipo debe cambiar.
- "Cerrar registro" impide equipos nuevos cuando ya estén todos.
- Contraseñas con bcrypt; sesiones de 6 h; las tablas no son accesibles directamente.
