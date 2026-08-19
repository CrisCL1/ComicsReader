# Onyx

Lector y biblioteca de PDFs para iPhone. Diseño minimalista sobre negro con
acentos suaves (arena `#C9B79C` y niebla `#8FA1B3`).

## Qué hace

| Pestaña | Función |
|---|---|
| **Biblioteca** | Todos tus PDFs con % leído, página actual, etiquetas personalizadas, búsqueda y filtros (en curso / sin empezar / terminados). |
| **Favoritos** | Los marcados con estrella. |
| **Buscar** | Navegador integrado. Abre cualquier web; si sirve un PDF, Onyx lo intercepta y lo guarda en la biblioteca en vez de abrirlo en el visor del sistema. El botón «Buscar PDF» escanea la página en busca de enlaces `.pdf`. |
| **Ajustes** | Google Drive (conectar, subida automática, liberar espacio), gestor de etiquetas, uso de almacenamiento. |

### Tres formas de meter un PDF

1. **Navegador integrado** — pestaña *Buscar*, abres la web y descargas. Usa las
   cookies de la sesión, así que funciona en sitios donde hay que iniciar sesión.
2. **Hoja de compartir de Safari** — en Safari, con el PDF abierto: *Compartir →
   Copiar en Onyx*.
3. **Archivos** — biblioteca → menú `···` → *Importar PDF*.

### Google Drive

Opcional. Al conectarlo, cada PDF se copia a una carpeta `Onyx` en tu Drive.
Con *Liberar espacio tras subir* activado, el archivo local se borra y solo
queda la ficha (título, portada, progreso, etiquetas); al abrirlo, se descarga
de nuevo. Así el iPhone no se satura.

El permiso pedido es `drive.file`: la app **solo ve los archivos que ella misma
crea**, no el resto de tu Drive.

## Estructura

```
Onyx/
├── project.yml                    # spec de XcodeGen (genera el .xcodeproj)
├── App/
│   ├── OnyxApp.swift              # entrada, recibe PDFs compartidos
│   ├── Theme.swift                # paleta y componentes base
│   ├── Assets.xcassets/           # icono
│   ├── Models/
│   │   ├── LibraryItem.swift      # ficha de documento (progreso, tags, Drive)
│   │   └── LibraryStore.swift     # estado + persistencia en library.json
│   ├── Services/
│   │   ├── FileStore.swift        # rutas, miniaturas, tamaños
│   │   ├── BrowserModel.swift     # WKWebView + intercepción de descargas
│   │   ├── DriveConfig.swift      # ← aquí va tu Client ID de Google
│   │   ├── GoogleDriveAuth.swift  # OAuth 2.0 + PKCE, sin SDK externo
│   │   ├── GoogleDriveClient.swift# Drive API v3 (subida resumable)
│   │   ├── DriveSync.swift        # subir / liberar espacio / recuperar
│   │   └── Keychain.swift
│   ├── Views/                     # SwiftUI
│   └── Support/Info.plist
└── .github/workflows/build-ipa.yml
```

Sin dependencias externas: solo SwiftUI, PDFKit, WebKit y CryptoKit.
Mínimo iOS 16.

## Instalación

Ver **[INSTALL.md](INSTALL.md)**.

## Limitaciones conocidas

- Solo maneja **PDF**. Si una web entrega `.zip`, `.cbz` o imágenes sueltas, no
  se importa (habría que añadir un conversor).
- Sitios tras Cloudflare con verificación de bot pueden bloquear el navegador
  integrado igual que bloquearían a Safari.
- El progreso se guarda por documento en el dispositivo; no se sincroniza entre
  dispositivos aunque el PDF esté en Drive.
