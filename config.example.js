// ==============================================================
//  PLANTILLA DE CONFIGURACIÓN
//  Copia este archivo como "config.js" (en la misma carpeta) y
//  reemplaza los valores con los de tu proyecto de Supabase.
//  Ver GUIA-SUPABASE.md, paso "Copiar las claves".
//  config.js está en .gitignore: nunca se sube al repositorio.
// ==============================================================
window.APP_CONFIG = {
  SUPABASE_URL:      'PEGA_AQUI_TU_PROJECT_URL',      // solo la raíz, sin /rest/v1/
  SUPABASE_ANON_KEY: 'PEGA_AQUI_TU_ANON_PUBLIC_KEY',  // clave larga "anon public"
  // Correos con los que crearon los usuarios en Supabase → nombre que se muestra
  USUARIOS: {
    'correo-de-ella@ejemplo.com': 'Nombre1',
    'correo-de-el@ejemplo.com':   'Nombre2'
  }
};
