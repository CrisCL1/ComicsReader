# Instalar Onyx en tu iPhone

Apple no permite instalar apps propias sin pasar por Xcode o por una
herramienta de sideload. Hay dos caminos según tengas o no un Mac.

---

## Ruta A — Con un Mac (la más simple)

Requisitos: macOS con **Xcode 15+**, cable USB, tu Apple ID (gratis vale).

```bash
brew install xcodegen
cd Onyx
xcodegen generate
open Onyx.xcodeproj
```

1. En Xcode: selecciona el target **Onyx** → pestaña **Signing & Capabilities**.
2. Marca *Automatically manage signing* y elige tu Apple ID en **Team**
   (Xcode → Settings → Accounts → `+` si aún no está).
3. Cambia el **Bundle Identifier** a algo único tuyo, por ejemplo
   `com.cris.onyx.<algo>`. Debe coincidir con el que uses en Google Cloud.
4. Conecta el iPhone, elígelo como destino y pulsa ▶.
5. En el iPhone: **Ajustes → General → VPN y gestión de dispositivos** →
   confía en tu certificado de desarrollador.

> Si no tienes XcodeGen: crea un proyecto nuevo *App / SwiftUI* en Xcode,
> borra los archivos que genera y arrastra la carpeta `App/` completa al
> proyecto (marcando *Copy items if needed*), y usa `App/Support/Info.plist`.

---

## Ruta B — Sin Mac, solo desde Windows

Se compila en la nube y se instala con SideStore. Es más largo pero funciona.

### B.1 — Compilar el .ipa en GitHub

1. Crea una cuenta en github.com y un repositorio **público** (los runners
   macOS son gratis en repos públicos).
2. Sube la carpeta `Onyx` al repositorio (web: *Add file → Upload files*, o
   con Git). Asegúrate de que `.github/workflows/build-ipa.yml` viaja también.
3. Pestaña **Actions** → *Build unsigned IPA* → **Run workflow**.
4. Cuando termine (~5 min), descarga el artefacto `Onyx-unsigned-ipa`.
   Dentro está `Onyx-unsigned.ipa`.

### B.2 — Instalarlo con SideStore

1. En el PC instala **iTunes** (versión de Apple, no la de Microsoft Store) y
   **iCloud para Windows** — SideStore los necesita para el emparejamiento.
2. Descarga **SideStore** desde `sidestore.io` y sigue su guía de
   emparejamiento (genera un archivo `.mobiledevicepairing` desde el PC y lo
   copia al iPhone).
3. Instala SideStore en el iPhone y firma con tu Apple ID.
4. En SideStore: `+` → elige `Onyx-unsigned.ipa`.

> **Alternativa**: AltStore Classic también tiene AltServer para Windows y
> funciona igual.

---

## Lo que hay que saber sí o sí

| | Apple ID gratis | Cuenta de desarrollador ($99/año) |
|---|---|---|
| Caducidad de la app | **7 días** — hay que refirmar | 1 año |
| Apps sideloadeadas a la vez | 3 | 10 |
| Refirmado automático | Sí, con SideStore/AltStore abierto y en la misma red Wi-Fi que el PC | Igual |

Con cuenta gratis la app **deja de abrirse a los 7 días** hasta que la
refirmes. SideStore/AltStore lo hacen solos en segundo plano si el servidor
está encendido; si no, se hace a mano en un minuto. Tus PDFs y tu progreso no
se pierden al refirmar (solo si desinstalas).

---

## Configurar Google Drive (opcional)

Si no haces esto, la app funciona igual pero solo con almacenamiento local.

1. Entra en **console.cloud.google.com** y crea un proyecto.
2. *APIs y servicios → Biblioteca* → habilita **Google Drive API**.
3. *Pantalla de consentimiento de OAuth*: tipo **Externo**, déjala en modo
   **Pruebas** y añádete a ti mismo en **Usuarios de prueba**. En modo pruebas
   no necesitas verificación de Google.
4. *Credenciales → Crear credenciales → ID de cliente de OAuth → iOS*.
   - **ID del paquete**: exactamente el mismo Bundle Identifier de la app
     (`com.cris.onyx` por defecto).
5. Copia el **ID de cliente**, con esta pinta:
   `123456789012-abcdefghijk.apps.googleusercontent.com`

Ahora dos ediciones:

**`App/Services/DriveConfig.swift`**
```swift
static let clientID = "123456789012-abcdefghijk.apps.googleusercontent.com"
```

**`App/Support/Info.plist`** — dentro de `CFBundleURLSchemes`, pon el ID
**invertido** (el mismo, sin `.apps.googleusercontent.com`, precedido por
`com.googleusercontent.apps.`):
```xml
<string>com.googleusercontent.apps.123456789012-abcdefghijk</string>
```

Recompila. En *Ajustes → Conectar Google Drive* se abrirá la pantalla de
Google; al aceptar verás un aviso de "app no verificada" — es normal en modo
pruebas, continúa.

> Aviso de Google: los proyectos en modo *Pruebas* caducan el refresh token
> cada 7 días, así que tendrás que volver a conectar la cuenta cada semana.
> Publicar la app en modo *Producción* elimina eso, pero `drive.file` es un
> permiso no sensible, así que la publicación suele aprobarse sin auditoría.

---

## Cambiar el Bundle Identifier

Aparece en tres sitios y deben coincidir:

- `project.yml` → `PRODUCT_BUNDLE_IDENTIFIER`
- Google Cloud → ID del paquete del cliente OAuth
- Xcode → Signing & Capabilities (si usas la Ruta A)

---

## Solución de problemas

**"Untrusted Developer" al abrir la app**
Ajustes → General → VPN y gestión de dispositivos → confía en el perfil.

**La app se cierra sola al abrirla, pasados unos días**
Caducó la firma de 7 días. Refírmala desde SideStore/AltStore.

**El navegador integrado muestra el PDF en vez de descargarlo**
No debería: `BrowserModel` fuerza `.download` para cualquier respuesta con
MIME `application/pdf`. Si una web devuelve el PDF con un MIME incorrecto,
usa el botón «Buscar PDF» y elige el enlace a mano.

**"No se encontraron PDFs enlazados"**
Esa web probablemente no sirve PDFs (muchos lectores online entregan imágenes
sueltas o `.zip`/`.cbz`). Onyx solo importa PDF.

**El build de GitHub falla**
Mira el log del paso *Compilar*. Lo más común es un `DEVELOPMENT_TEAM`
rellenado por error en `project.yml`: debe quedar vacío para el build sin firma.
