# Botiquín

App para llevar el inventario del botiquín de casa, consultar síntomas contra lo que tenés y encontrar farmacias cerca. Pensada para usar desde el teléfono, en España.

Versión actual publicada como artifact de Claude: https://claude.ai/artifact/GPco5ryp6xzoicDzpPYTsv

Todo el código está en `index.html` (HTML, CSS y JavaScript en un solo archivo, sin dependencias salvo Google Fonts).

## Qué hace

- **Botiquín**: lista de medicamentos ordenada por vencimiento, con estado (ok / vence en ≤60 días / vencido), búsqueda, editar y borrar.
- **Agregar**: foto de las cajas (cámara o galería, hasta 8 por tanda). Claude lee nombre, principio activo, presentación, cantidad, caducidad, para qué sirve y si requiere receta. Se revisa en un formulario y se guarda. También se puede cargar a mano.
- **Consultar**: síntoma en texto (con foto opcional). Claude revisa el inventario, descarta vencidos, sugiere qué usar con dosis orientativa (producto recomendado en negrita), qué comprar sin receta en España si no hay nada, y señales de alarma. Lo que sugiere comprar va a la "Lista para la farmacia". Cada consulta queda guardada en "Consultas anteriores" (fecha, síntoma, respuesta, compras), con opción de borrar.
- **Farmacias**: botón "Buscar farmacias donde estoy" (intenta GPS; si no se puede, abre Google Maps con "cerca de mí" y Maps usa la ubicación del teléfono), enlaces a guardia 24 h, Apple Maps, farmaciasdeguardia.org, y campo opcional para buscar alrededor de otra dirección. Lista de compras con "Copiar".

## Datos

Hoy se guardan en la base de datos del artifact de Claude (`window.claude.use("db")`, API estilo Firestore):

| Colección / documento | Contenido |
|---|---|
| `medicamentos` | `id`, `nombre`, `principio`, `presentacion`, `cantidad`, `vencimiento` (YYYY-MM), `uso`, `receta` (bool), `agregado` (YYYY-MM-DD) |
| `consultas` | `id`, `fecha` (ISO), `sintoma`, `conFoto` (bool), `respuesta`, `compras` (array de strings) |
| `config/compras` | `{ items: [{ id, nombre, motivo }] }` |
| `config/ubicacion` | `{ direccion }` |

Si no hay base de datos disponible, todo se guarda en `localStorage` (claves `botiquin.meds`, `botiquin.shop`, `botiquin.hist`, `botiquin.addr`, `botiquin.tab`).

## Dependencias del entorno de Claude

El código usa capacidades que solo existen dentro de claude.ai:

- `window.claude.use("db")`: base de datos sincronizada.
- `window.claude.use("sample")`: llamadas a Claude (`sample(prompt, opts)` para texto con streaming y `sample.json(prompt, opts)` para JSON), con imágenes.
- La sesión del usuario de claude.ai (capacidad `user`).

Fuera de Claude estas llamadas devuelven `undefined`: la app sigue funcionando con `localStorage`, pero sin lectura de cajas ni consultas.

## Limitaciones conocidas

- Dentro del marco de Claude la página no puede leer el GPS del teléfono; la ubicación la usa la app de Maps al abrir el enlace.
- Pendiente: botiquín compartido con amigos.

## Plan de migración (Supabase)

1. **Página**: publicar `index.html` en un hosting estático gratis (Netlify, Vercel o GitHub Pages). Supabase no sirve bien páginas web.
2. **Datos**: crear tablas `medicamentos`, `consultas`, `compras` y `ubicacion` en Supabase (Postgres) y reemplazar las llamadas a `db` por el cliente `supabase-js`.
3. **Usuarios**: Supabase Auth (email o Google) con Row Level Security por usuario. Deja preparado el botiquín compartido.
4. **Claude**: reemplazar `sample` por una Edge Function de Supabase que llame a la API de Anthropic. La clave de la API va como secreto en la función, nunca en la página. La API se paga por uso.
5. **GPS**: fuera del marco de Claude `navigator.geolocation` funciona normalmente.
6. **Ojo**: los proyectos del plan gratis de Supabase se pausan tras un tiempo sin actividad.
