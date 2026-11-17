// Datos públicos del proyecto de Supabase (Project Settings → API).
// La clave anon/publishable PUEDE ir en la página: la seguridad la dan las políticas RLS.
// Nunca pongas acá la service_role key ni la clave de Anthropic.
export const SUPABASE_URL = "https://oxrogurhrrfkjrprwjls.supabase.co";
export const SUPABASE_ANON_KEY = "sb_publishable_DoYwXdNaL8r0KBGkh7M1tA_x6atTlFV";

// Poné true cuando el proveedor Google esté activado en Supabase (Authentication → Providers → Google).
export const LOGIN_GOOGLE = true;
// Poné true cuando haya SMTP propio configurado en Supabase (link/código por email sin el límite del plan gratis).
export const LOGIN_LINK = false;
