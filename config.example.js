// ==============================================================
//  PLANTILLA DE CONFIGURACIÓN
//  Copia este archivo como "config.js" (en la misma carpeta) y
//  reemplaza los valores con los de tu proyecto de Supabase.
//  Ver GUIA-SUPABASE.md, paso "Copiar las claves".
//  config.js está en .gitignore: nunca se sube al repositorio.
//
//  Aquí NO van correos ni nombres. Cada persona escoge el suyo al
//  entrar y se guarda en la tabla "miembros", protegida por las
//  políticas RLS: la app lo lee después del login.
// ==============================================================
window.APP_CONFIG = {
  SUPABASE_URL:      'PEGA_AQUI_TU_PROJECT_URL',     // solo la raíz, sin /rest/v1/
  SUPABASE_ANON_KEY: 'PEGA_AQUI_TU_ANON_PUBLIC_KEY'  // clave larga "anon public"
};
