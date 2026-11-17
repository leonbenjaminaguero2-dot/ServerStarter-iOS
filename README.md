# ServerStarter para iPhone

Servidor HTTP local `http://localhost:8080`, app nativa Swift + UIKit + Network.framework.

## Navegación

Barra inferior con **Servidor**, **Editor** y **Ajustes**, siguiendo la pantalla de referencia. El editor modifica el `index.html` que sirve el servidor; Ajustes contiene pantalla siempre activa, estado, contador y solicitudes recientes.

## Funciones incluidas

- Seleccioná un `.html` desde **Archivos**: se guarda como `Documents/ServerStarterSite/index.html`.
- Si todavía no hay HTML, el editor ofrece una página inicial que podés modificar y guardar.
- Importá CSS, JS e imágenes en la misma carpeta para utilizar rutas relativas.
- Iniciá el servidor en `127.0.0.1:8080` y mirá su estado y peticiones.
- **TERMINAR SERVIDOR** cancela el listener y todas las conexiones abiertas, impidiendo un reinicio automático involuntario.
- Sección **Página web** con botón **Vista previa**: si el servidor está detenido, lo inicia automáticamente y abre `http://localhost:8080` en un `WKWebView` dentro de la app; incorpora controles **cerrar**, **recargar** y **terminar servidor**.
- Liquid Glass **nativo y sobrio** (`UIGlassEffect`, `UIButton.Configuration.glass()` y `.prominentGlass()`) en iOS **26 o superior**; controles de cristal limitados a botones, estado y barra de vista previa. Fondos opacos neutros en las secciones de contenido. En iOS 16–25 se usan materiales translúcidos nativos.
- Ícono azul ServerStarter. Botón **Terminar servidor** rojo, **Iniciar servidor** verde y **Vista previa** cian; colores del sistema discretos con Liquid Glass nativo.
- Selector **Mantener pantalla encendida** para uso prolongado mientras la app está visible (consume batería).
- Copiar la URL al portapapeles.

## LiveContainer

- La app no requiere JIT: usa UIKit, WebKit, Foundation y Network.framework.
- El proyecto apunta a iOS 16 o posterior y conserva el selector de documentos y el servidor loopback en `127.0.0.1`.
- La IPA de GitHub Actions se importa en LiveContainer y se inicia desde allí. La compatibilidad final depende de la versión de LiveContainer/iOS; probá el selector de archivos y `http://localhost:8080` en el dispositivo.
- LiveContainer documenta que los permisos de la app invitada se aplican globalmente y que algunas apps no son compatibles. Si Archivos no abre, activá **Fix File Picker** en los ajustes de ServerStarter dentro de LiveContainer.

## Segundo plano: limitación real de iOS

- Al entrar en segundo plano, ServerStarter solicita un tiempo de ejecución **limitado** con `beginBackgroundTask(withName:expirationHandler:)` para permitir que se completen solicitudes de red.
- Cuando iOS señala que el tiempo vence, el servidor cierra sus conexiones y pasa a **PAUSADO POR iOS**.
- Cuando volvés a la app, el listener se reinicia si vos no tocaste **TERMINAR SERVIDOR**.
- **No puede garantizarse un servidor HTTP continuo en segundo plano o con el iPhone bloqueado**, ni con JIT, SideStore o LiveContainer. Apple solo autoriza modos de fondo persistentes para actividades especiales. No incluimos modos de fondo falsos (VoIP/audio/localización).
- El botón de detener funciona mientras podés interactuar con la app; si la app está suspendida, iOS no ejecuta controles hasta que vuelve al primer plano.

## Generar una IPA sin Mac desde GitHub Actions

1. Subí el **contenido de este proyecto** (incluida la carpeta `.github`) a un repositorio propio. **No hace falta borrar ni modificar BootMaker.**
2. Abrí **GitHub → Actions → Compilar IPA - ServerStarter → Run workflow**.
3. El workflow usa un runner `macos-26` con Xcode, instala XcodeGen, compila para iPhone y empaqueta la app.
4. Descargá el artifact `ServerStarter-unsigned-IPA` y extraé `ServerStarter-unsigned.ipa`.
5. Importá la IPA en LiveContainer. Para iniciar sin JIT, configurá primero el certificado de firma de LiveContainer; también podés firmarla con SideStore antes de importarla.

**Este proyecto fuente no contiene una IPA compilada.** La compilación requiere macOS/Xcode y la prueba final de LiveContainer debe hacerse en un iPhone real.

## Detalles

- Solo atiende HTTP/1.1 para GET y HEAD; no incorpora TLS ni APIs backend complejas.
- Escucha solo en `127.0.0.1`, **no permite conexiones desde otros dispositivos**.
- No modifica nada de la IPA original de BootMaker.
- La importación individual no preserva subcarpetas y no descomprime archivos ZIP.
- Si `8080` está ocupado, muestra un error.
