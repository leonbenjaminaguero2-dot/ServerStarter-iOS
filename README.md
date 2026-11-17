# ServerStarter para iPhone

Servidor HTTP local `http://localhost:8080`, app nativa Swift + UIKit + Network.framework.

## Navegación

Barra inferior nativa con **Servidor** y **Estado** (sin Editor ni Ajustes). En Estado aparecen el estado actual del servidor, el contador de solicitudes y los últimos registros.

## Funciones incluidas

- Seleccioná un `.html` desde **Archivos**: se guarda como `Documents/ServerStarterSite/index.html`.
- Importá CSS, JS e imágenes en la misma carpeta para utilizar rutas relativas.
- Iniciá el servidor en `127.0.0.1:8080` y mirá su estado y peticiones.
- **TERMINAR SERVIDOR** cancela el listener y todas las conexiones abiertas, impidiendo un reinicio automático involuntario.
- Sección **Página web** con botón **Vista previa**: si el servidor está detenido, lo inicia automáticamente y abre `http://localhost:8080` en un `WKWebView` dentro de la app; incorpora controles **cerrar**, **recargar** y **terminar servidor**.
- Liquid Glass **nativo y sobrio** (`UIGlassEffect`, `UIButton.Configuration.glass()` y `.prominentGlass()`) en iOS **26 o superior**; controles de cristal limitados a botones, estado y barra de vista previa. Fondos opacos neutros en las secciones de contenido. En iOS 16–25 se usan materiales translúcidos nativos.
- Ícono azul ServerStarter. Botón **Terminar servidor** rojo, **Iniciar servidor** verde y **Vista previa** cian; colores del sistema discretos con Liquid Glass nativo.
- Selector **Mantener pantalla encendida** para uso prolongado mientras la app está visible (consume batería).
- Copiar la URL al portapapeles.

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
5. Firmá la IPA mediante SideStore u otra herramienta compatible antes de instalar.

**Este ZIP es el proyecto fuente; NO contiene una IPA compilada.** Acá se verificó la sintaxis de todos los Swift y la estructura del proyecto, pero la compilación iOS requiere macOS/Xcode y la prueba final en un iPhone real.

## Detalles

- Solo atiende HTTP/1.1 para GET y HEAD; no incorpora TLS ni APIs backend complejas.
- Escucha solo en `127.0.0.1`, **no permite conexiones desde otros dispositivos**.
- No modifica nada de la IPA original de BootMaker.
- La importación individual no preserva subcarpetas y no descomprime archivos ZIP.
- Si `8080` está ocupado, muestra un error.
