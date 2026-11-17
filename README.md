# Botiquín

App para llevar el inventario del botiquín de casa, consultar síntomas contra lo que tenés y encontrar farmacias cerca. Pensada para usar desde el teléfono, en España.

**App:** <https://wlacaze-git.github.io/botiquin/>

- **Página**: `index.html` + `config.js`, estática, publicada en GitHub Pages. Sin paso de build.
- **Datos y login**: Supabase (Postgres + Auth). Se entra con un link por email y, cuando esté configurado, con Google. Cada usuario ve solo sus botiquines (Row Level Security).
- **IA**: la Edge Function `asistente` llama a la API de DeepSeek. La clave está solo en la función, como secreto.

```
GitHub Pages (index.html)  ──►  Supabase Auth (email / Google)
          │
          ├──► Supabase Postgres (tablas + RLS)
          └──► Edge Function "asistente" ──► API de DeepSeek
```

Proyecto de Supabase: `botiquin` (ref `oxrogurhrrfkjrprwjls`, región eu-west-3 / París).

## Qué hace

- **Botiquín**: lista de medicamentos ordenada por vencimiento, con estado (ok / vence en ≤60 días / vencido), búsqueda, editar y borrar. Se sincroniza en vivo entre dispositivos.
- **Agregar**: fotos de las cajas (cámara o galería, hasta 8 por tanda; se achican en el teléfono antes de enviarlas). La IA lee nombre, principio activo, presentación, cantidad, caducidad, para qué sirve y si requiere receta. Se revisa en un formulario y se guarda. También se puede cargar a mano.
- **Consultar**: síntoma en texto (con foto opcional). La IA revisa el inventario, descarta vencidos, sugiere qué usar, qué comprar sin receta y señales de alarma. Lo que sugiere comprar va a la "Lista para la farmacia". Las consultas quedan guardadas y **son privadas de cada usuario**, aunque el botiquín sea compartido.
- **Farmacias**: GPS del teléfono → Google Maps / Apple Maps, guardias 24 h, otra dirección, lista de compras con "Copiar".
- **Cuenta** (botón redondo arriba a la derecha): renombrar el botiquín, **compartirlo** con un enlace de invitación (7 días), unirse con un código, descargar una copia en JSON, importar datos y cerrar sesión.

## Estructura

| Archivo | Qué es |
|---|---|
| `index.html` | Toda la app (HTML, CSS y JS). Carga `supabase-js` desde jsDelivr. |
| `config.js` | URL del proyecto y clave publishable (públicas), y `LOGIN_GOOGLE`. |
| `supabase/migrations/20261117000000_esquema.sql` | Tablas, RLS, funciones RPC y Realtime. |
| `supabase/functions/asistente/index.ts` | Edge Function que habla con DeepSeek. |
| `supabase/config.toml` | Config de la CLI (URLs de Auth, función). |
| `.env.local` | **Local, no se sube.** Contraseña de la base y claves para cargar como secretos. |

### Base de datos

| Tabla | Contenido |
|---|---|
| `botiquines` | `id`, `nombre`, `direccion`, `creado_por` |
| `miembros` | `botiquin_id`, `user_id`, `rol` (`dueno`/`miembro`), `email` |
| `medicamentos` | `nombre`, `principio`, `presentacion`, `cantidad`, `vencimiento` (`YYYY-MM`), `uso`, `receta`, `agregado` |
| `consultas` | `user_id`, `fecha`, `sintoma`, `con_foto`, `respuesta`, `compras[]` (solo las ve quien las hizo) |
| `compras` | `nombre`, `motivo` (sin repetidos por botiquín) |
| `invitaciones` | códigos para compartir (se manejan solo por RPC) |
| `uso_claude` | llamadas a la IA por usuario y día (límite de gasto; el nombre quedó de la primera versión) |

Funciones RPC: `mi_botiquin()` (devuelve tus botiquines y crea uno la primera vez), `crear_invitacion(b)`, `unirse(codigo)`, `consumir_cuota(limite)`.

### Edge Function `asistente`

- Verifica la sesión, cuenta la llamada contra el límite diario (`LIMITE_DIARIO`, 40 por defecto) y arma los prompts del lado del servidor. La página solo manda datos, así que la función no sirve como chatbot de uso general.
- `leer_cajas`: pide JSON (`response_format: json_object`) y lo valida antes de devolverlo.
- `consulta`: lee el inventario de la base con la sesión del usuario, responde en streaming (NDJSON) y al final guarda la consulta y agrega las compras.
- Modelo: `deepseek-flash` (acepta imágenes). Se cambia con los secretos `DEEPSEEK_MODEL` y `DEEPSEEK_MODEL_CAJAS`.

## Configuración pendiente

### Clave de DeepSeek (obligatoria para leer cajas y consultar)

1. Creá una cuenta en <https://platform.deepseek.com/>, cargá saldo (es prepago) y creá una API key.
2. Cargala como secreto de la función: `npx supabase secrets set DEEPSEEK_API_KEY=sk-...` (o pegala en `.env.local` y pedile a Claude Code que la cargue).

### Login con Google (opcional; mientras tanto se entra por email)

1. En <https://console.cloud.google.com/> creá un proyecto. En **Google Auth Platform / OAuth consent screen**: tipo *External*, nombre "Botiquín", tu email. En *Test users* agregá las cuentas que van a entrar.
2. **Credentials → Create credentials → OAuth client ID → Web application**:
   - *Authorized JavaScript origins*: `https://wlacaze-git.github.io`
   - *Authorized redirect URIs*: `https://oxrogurhrrfkjrprwjls.supabase.co/auth/v1/callback`
3. Pegá el Client ID y el Secret en `.env.local` y agregá esto a `supabase/config.toml`:
   ```toml
   [auth.external.google]
   enabled = true
   client_id = "env(GOOGLE_CLIENT_ID)"
   secret = "env(GOOGLE_CLIENT_SECRET)"
   ```
   Después: `npx supabase config push`, y en `config.js` poné `LOGIN_GOOGLE = true`.

### Login por email: límites del plan gratis

El servidor de correo que trae Supabase en el plan gratis manda pocos emails por hora y solo a los miembros del equipo de la organización de Supabase. Para que entren otras personas, activá Google o configurá un SMTP propio (por ejemplo Resend, que tiene plan gratis) en **Authentication → Emails → SMTP Settings**.

## Pasar los datos de la versión anterior

1. Abrí la versión anterior (artifact de Claude: <https://claude.ai/artifact/GPco5ryp6xzoicDzpPYTsv>), andá a **Farmacias → Exportar mis datos** y tocá **Exportar**. El texto se copia al portapapeles.
2. En la app nueva, entrá, tocá el botón redondo de arriba a la derecha → **Tus datos → Importar datos**, pegá el texto y tocá **Importar**.

## Desarrollo

```bash
python -m http.server 8000      # o: npx serve -l 8000
```

Abrí <http://localhost:8000/>. Ya está en las Redirect URLs de Supabase y en `ORIGENES_PERMITIDOS`.

Cambios en el backend:

```bash
npx supabase db push --remote                 # nuevas migraciones
npx supabase functions deploy asistente       # la función
npx supabase config push                      # URLs y proveedores de Auth
```

## Para tener en cuenta

- **Costo**: Supabase y GitHub Pages son gratis en este uso. DeepSeek es prepago y barato. El límite diario por usuario (`LIMITE_DIARIO`) acota el gasto.
- **Pausa del plan gratis**: Supabase pausa los proyectos gratis tras unos días sin actividad. Se reactivan desde el dashboard.
- **Datos de salud y DeepSeek**: DeepSeek procesa los datos en servidores en China. Los síntomas y las fotos que se consultan salen de la UE. Las consultas guardadas son privadas por usuario, las fotos no se guardan y RLS impide ver botiquines ajenos.
- **La clave publishable en `config.js` es pública a propósito**: no da acceso a nada sin sesión y RLS. Nunca pongas ahí la `service_role`/secret key ni la de DeepSeek.
