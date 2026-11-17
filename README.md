# Botiquín

App para llevar el inventario del botiquín de casa, consultar síntomas contra lo que tenés y encontrar farmacias cerca. Pensada para usar desde el teléfono, en España.

- **Página**: `index.html` + `config.js`, estática, publicada en GitHub Pages. Sin paso de build.
- **Datos y login**: Supabase (Postgres + Auth con Google). Cada usuario ve solo sus botiquines (Row Level Security).
- **Claude**: una Edge Function de Supabase (`supabase/functions/claude`) llama a la API de Anthropic. La clave de la API está solo ahí, como secreto.

```
GitHub Pages (index.html)  ──►  Supabase Auth (Google)
          │
          ├──► Supabase Postgres (tablas + RLS)
          └──► Edge Function "claude" ──► API de Anthropic
```

## Qué hace

- **Botiquín**: lista de medicamentos ordenada por vencimiento, con estado (ok / vence en ≤60 días / vencido), búsqueda, editar y borrar. Se sincroniza en vivo entre dispositivos.
- **Agregar**: fotos de las cajas (cámara o galería, hasta 8 por tanda; se achican en el teléfono antes de enviarlas). Claude lee nombre, principio activo, presentación, cantidad, caducidad, para qué sirve y si requiere receta. Se revisa en un formulario y se guarda. También se puede cargar a mano.
- **Consultar**: síntoma en texto (con foto opcional). Claude revisa el inventario, descarta vencidos, sugiere qué usar, qué comprar sin receta y señales de alarma. Lo que sugiere comprar va a la "Lista para la farmacia". Las consultas quedan guardadas y **son privadas de cada usuario**, aunque el botiquín sea compartido.
- **Farmacias**: GPS del teléfono → Google Maps / Apple Maps, guardias 24 h, otra dirección, lista de compras con "Copiar".
- **Cuenta** (botón redondo arriba a la derecha): renombrar el botiquín, **compartirlo** con un enlace de invitación (7 días), unirse con un código, descargar una copia en JSON, importar datos y cerrar sesión.

## Estructura

| Archivo | Qué es |
|---|---|
| `index.html` | Toda la app (HTML, CSS y JS). Carga `supabase-js` desde jsDelivr. |
| `config.js` | URL del proyecto de Supabase y clave anon/publishable (públicas). |
| `supabase/migrations/20261117000000_esquema.sql` | Tablas, RLS, funciones RPC y Realtime. |
| `supabase/functions/claude/index.ts` | Edge Function que habla con Claude. |
| `supabase/config.toml` | Config mínima para la CLI. |

### Base de datos

| Tabla | Contenido |
|---|---|
| `botiquines` | `id`, `nombre`, `direccion`, `creado_por` |
| `miembros` | `botiquin_id`, `user_id`, `rol` (`dueno`/`miembro`), `email` |
| `medicamentos` | `nombre`, `principio`, `presentacion`, `cantidad`, `vencimiento` (`YYYY-MM`), `uso`, `receta`, `agregado` |
| `consultas` | `user_id`, `fecha`, `sintoma`, `con_foto`, `respuesta`, `compras[]` (solo las ve quien las hizo) |
| `compras` | `nombre`, `motivo` (sin repetidos por botiquín) |
| `invitaciones` | códigos para compartir (se manejan solo por RPC) |
| `uso_claude` | llamadas a Claude por usuario y día (límite de gasto) |

Funciones RPC: `mi_botiquin()` (devuelve tus botiquines y crea uno la primera vez), `crear_invitacion(b)`, `unirse(codigo)`, `consumir_cuota(limite)`.

### Edge Function `claude`

- Verifica la sesión, cuenta la llamada contra el límite diario (`LIMITE_DIARIO`, 40 por defecto) y arma los prompts del lado del servidor. La página solo manda datos, así que la función no sirve como un Claude de uso general.
- `leer_cajas`: devuelve JSON validado con un esquema (structured outputs).
- `consulta`: lee el inventario de la base con la sesión del usuario, responde en streaming (NDJSON) y al final guarda la consulta y agrega las compras.
- Modelos: las consultas usan `claude-opus-5-5` (secreto `CLAUDE_MODEL`), con fallback del lado del servidor si el modelo rechaza la consulta. La lectura de cajas usa `claude-haiku-5-5` (secreto `CLAUDE_MODEL_CAJAS`): unos 0,2 céntimos por tanda de 8 fotos.
- ¿Por qué no Gemini gratis? Las condiciones de Google prohíben usar el plan gratuito en apps para usuarios del EEE (España incluida) y, en ese plan, Google puede usar lo que se le manda para mejorar sus productos.

## Puesta en marcha

Hace falta una cuenta de Supabase (plan gratis), un proyecto en Google Cloud (gratis, solo para el login), una clave de la API de Anthropic (se paga por uso) y el repo en GitHub.

### 1. Proyecto de Supabase

1. En <https://supabase.com/dashboard> creá un proyecto. Región en la UE (por ejemplo Frankfurt o París).
2. En **Project Settings → API** copiá la **Project URL** y la clave **anon** (o **publishable**) y pegalas en `config.js`.
3. Creá las tablas. Hay dos formas:
   - **SQL Editor**: pegá el contenido de `supabase/migrations/20261117000000_esquema.sql` y ejecutalo.
   - **CLI**: `npx supabase login`, después `npx supabase link --project-ref TU-REF` y `npx supabase db push`.

### 2. Login con Google

1. En <https://console.cloud.google.com/> creá un proyecto. En **APIs & Services → OAuth consent screen** configurá la pantalla de consentimiento (tipo External, con tu email de soporte). Mientras esté en modo *Testing*, agregá como *test users* las cuentas que van a entrar.
2. En **Credentials → Create credentials → OAuth client ID**, elegí tipo **Web application**:
   - *Authorized JavaScript origins*: `https://TU-USUARIO.github.io`
   - *Authorized redirect URIs*: `https://TU-REF.supabase.co/auth/v1/callback`
3. En Supabase, **Authentication → Sign In / Providers → Google**: activalo y pegá el *Client ID* y el *Client Secret*.
4. En Supabase, **Authentication → URL Configuration**:
   - *Site URL*: `https://TU-USUARIO.github.io/botiquin/`
   - *Redirect URLs*: la misma, y `http://localhost:8000/` para probar en tu compu.

### 3. Edge Function y secretos

```bash
npx supabase login
npx supabase link --project-ref TU-REF
npx supabase secrets set ANTHROPIC_API_KEY=sk-ant-... ORIGENES_PERMITIDOS=https://TU-USUARIO.github.io,http://localhost:8000
# opcionales:
npx supabase secrets set LIMITE_DIARIO=40 CLAUDE_MODEL=claude-opus-5-5 CLAUDE_MODEL_CAJAS=claude-haiku-5-5
npx supabase functions deploy claude
```

La clave de Anthropic se saca en <https://console.anthropic.com/> → API Keys. Conviene ponerle un límite de gasto mensual ahí mismo.

### 4. GitHub Pages

1. Subí el repo a GitHub con `config.js` completo.
2. En **Settings → Pages → Build and deployment**, elegí *Deploy from a branch*, rama `main` y carpeta `/ (root)`.
3. La app queda en `https://TU-USUARIO.github.io/botiquin/`.

### 5. Pasar los datos de la versión anterior

1. Abrí la versión anterior (artifact de Claude: <https://claude.ai/artifact/GPco5ryp6xzoicDzpPYTsv>), andá a **Farmacias → Exportar mis datos** y tocá **Exportar**. El texto se copia al portapapeles.
2. En la app nueva, entrá con Google, tocá el botón redondo de arriba a la derecha → **Tus datos → Importar datos**, pegá el texto y tocá **Importar**.

### Probar en tu compu

```bash
python -m http.server 8000      # o: npx serve -l 8000
```

y abrí <http://localhost:8000/>. Hace falta que `http://localhost:8000/` esté en las Redirect URLs de Supabase y en `ORIGENES_PERMITIDOS`.

## Para tener en cuenta

- **Costo**: Supabase y GitHub Pages son gratis en este uso. La API de Anthropic se paga por uso. El límite diario por usuario (`LIMITE_DIARIO`) y el límite de gasto en la consola de Anthropic acotan el gasto.
- **Pausa del plan gratis**: Supabase pausa los proyectos gratis tras unos días sin actividad. Se reactivan desde el dashboard.
- **Datos de salud**: son datos sensibles según el RGPD. Las consultas son privadas por usuario, las fotos no se guardan (solo se mandan a Claude) y RLS impide ver botiquines ajenos.
- **La clave anon en `config.js` es pública a propósito**: no da acceso a nada sin sesión y RLS. Nunca pongas ahí la `service_role` key ni la de Anthropic.
