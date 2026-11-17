import UIKit
import UniformTypeIdentifiers

/// ServerStarter: interfaz nativa. Liquid Glass real en iOS 26+.
/// No declara modos de fondo falsos (audio, ubicación, VoIP).
final class MainViewController: UIViewController, UIDocumentPickerDelegate, UITabBarDelegate {
    private enum ImportMode { case html, resources }

    private let server = LocalHTTPServer()
    private let accent = UIColor.systemCyan
    private let successColor = UIColor.systemGreen
    private let dangerColor = UIColor.systemRed
    private let muted = UIColor.secondaryLabel
    private let background = UIColor.systemGroupedBackground
    private let siteDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ServerStarterSite", isDirectory: true)

    private var importMode: ImportMode = .html
    private var running = false
    private var starting = false
    private var wantsServer = false
    private var pausedByIOS = false
    private var wasBackgrounded = false
    private var previewAfterStarting = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var lastStatus = "DETENIDO"
    private var lastLog = "Seleccioná tu archivo HTML"
    private var requests = 0
    private var requestHistory: [String] = []

    private let scroll = UIScrollView()
    private let serverSections = UIStackView()
    private let activitySections = UIStackView()
    private let navigationBar = UITabBar()
    private let activityStatusLabel = UILabel()
    private let recentRequestsLabel = UILabel()
    private let statusLabel = UILabel()
    private let selectedLabel = UILabel()
    private let resourcesLabel = UILabel()
    private let activityLabel = UILabel()
    private let logLabel = UILabel()
    private let countLabel = UILabel()
    private let keepAwakeToggle = UISwitch()
    private let startButton = UIButton(type: .system)
    private let stopButton = UIButton(type: .system)
    private let previewButton = UIButton(type: .system)
    private let copyButton = UIButton(type: .system)
    private let exampleButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = background
        do { try FileManager.default.createDirectory(at: siteDirectory, withIntermediateDirectories: true) }
        catch { lastLog = "Error creando carpeta: \(error.localizedDescription)" }

        configureInterface()
        server.onStatus = { [weak self] status in
            DispatchQueue.main.async { self?.updateServerStatus(status) }
        }
        server.onRequest = { [weak self] message in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.requests += 1
                self.lastLog = message
                let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
                self.requestHistory.insert("\(time)  \(message)", at: 0)
                if self.requestHistory.count > 25 { self.requestHistory.removeLast() }
                self.refresh()
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
        keepAwakeToggle.isOn = UserDefaults.standard.bool(forKey: "keepScreenOn")
        refresh()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        server.stop()
    }

    private func configureInterface() {
        scroll.alwaysBounceVertical = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)

        // UITabBar del sistema: Liquid Glass nativo donde lo admite iOS.
        // Dos pestañas: Servidor y Estado. No hay editor ni ajustes ficticios.
        navigationBar.translatesAutoresizingMaskIntoConstraints = false
        navigationBar.delegate = self
        navigationBar.items = [
            UITabBarItem(title: "Servidor", image: UIImage(systemName: "server.rack"), tag: 0),
            UITabBarItem(title: "Estado", image: UIImage(systemName: "info.circle.fill"), tag: 1)
        ]
        navigationBar.selectedItem = navigationBar.items?.first
        navigationBar.tintColor = accent
        navigationBar.unselectedItemTintColor = muted
        view.addSubview(navigationBar)

        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 17
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: navigationBar.topAnchor),
            navigationBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigationBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            navigationBar.heightAnchor.constraint(equalToConstant: 56),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 22),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -34),
            content.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            content.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
        ])

        for sectionStack in [serverSections, activitySections] {
            sectionStack.axis = .vertical
            sectionStack.spacing = 17
            content.addArrangedSubview(sectionStack)
        }
        activitySections.isHidden = true

        serverSections.addArrangedSubview(label("NEXORA · UTILIDADES", size: 12, weight: .semibold, color: accent))
        serverSections.addArrangedSubview(label("ServerStarter", size: 33, weight: .bold, color: .label))
        serverSections.addArrangedSubview(label("Tu servidor web local", size: 15, weight: .regular, color: muted))

        let statusPanel = makePanel()
        statusPanel.addArrangedSubview(label("Estado del servidor", size: 13, weight: .medium, color: muted))
        statusLabel.font = .monospacedSystemFont(ofSize: 19, weight: .bold)
        statusPanel.addArrangedSubview(statusLabel)
        let url = label("http://localhost:8080", size: 16, weight: .semibold, color: .white)
        url.font = .monospacedSystemFont(ofSize: 16, weight: .semibold)
        url.adjustsFontSizeToFitWidth = true
        url.minimumScaleFactor = 0.76
        statusPanel.addArrangedSubview(url)
        activityLabel.font = .systemFont(ofSize: 12, weight: .regular)
        activityLabel.textColor = muted
        activityLabel.numberOfLines = 0
        statusPanel.addArrangedSubview(activityLabel)
        serverSections.addArrangedSubview(statusPanel)

        serverSections.addArrangedSubview(section("01", "Archivos"))
        let filePanel = makePlainPanel()
        selectedLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        selectedLabel.textColor = .white
        selectedLabel.numberOfLines = 2
        filePanel.addArrangedSubview(selectedLabel)
        resourcesLabel.font = .systemFont(ofSize: 13)
        resourcesLabel.textColor = muted
        resourcesLabel.numberOfLines = 0
        filePanel.addArrangedSubview(resourcesLabel)
        filePanel.addArrangedSubview(makeButton("Elegir HTML", symbol: "doc.text", action: #selector(selectHTML), emphasized: false))
        filePanel.addArrangedSubview(makeButton("Añadir CSS, JS e imágenes", symbol: "folder.badge.plus", action: #selector(selectResources), emphasized: false))
        exampleButton.setTitle("Usar página de ejemplo", for: .normal)
        exampleButton.tintColor = accent
        exampleButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        exampleButton.contentHorizontalAlignment = .left
        exampleButton.addTarget(self, action: #selector(importExample), for: .touchUpInside)
        filePanel.addArrangedSubview(exampleButton)
        serverSections.addArrangedSubview(filePanel)

        serverSections.addArrangedSubview(section("02", "Control del servidor"))
        configureButton(startButton, title: "Iniciar servidor", symbol: "play.fill", emphasized: true, tint: successColor)
        startButton.addTarget(self, action: #selector(startServer), for: .touchUpInside)
        serverSections.addArrangedSubview(startButton)
        configureButton(stopButton, title: "Terminar servidor", symbol: "stop.fill", emphasized: true, tint: dangerColor)
        stopButton.addTarget(self, action: #selector(stopServer), for: .touchUpInside)
        serverSections.addArrangedSubview(stopButton)

        serverSections.addArrangedSubview(section("03", "Página web"))
        serverSections.addArrangedSubview(label("Abrí tu HTML en localhost:8080 sin salir de la app. Si el servidor está detenido, se inicia automáticamente.", size: 13, weight: .regular, color: muted))
        configureButton(previewButton, title: "Vista previa", symbol: "safari.fill", emphasized: true, tint: accent)
        previewButton.addTarget(self, action: #selector(openPreview), for: .touchUpInside)
        serverSections.addArrangedSubview(previewButton)
        configureButton(copyButton, title: "Copiar localhost:8080", symbol: "link", emphasized: false)
        copyButton.addTarget(self, action: #selector(copyURL), for: .touchUpInside)
        serverSections.addArrangedSubview(copyButton)

        serverSections.addArrangedSubview(section("04", "Segundo plano"))
        let backgroundPanel = makePlainPanel()
        backgroundPanel.addArrangedSubview(label("iOS puede suspender el servidor al salir de la app o bloquear el iPhone. ServerStarter intenta continuar por un tiempo limitado y reinicia el servidor al volver.", size: 13, weight: .regular, color: muted))
        let keepAwakeRow = UIStackView()
        keepAwakeRow.axis = .horizontal
        keepAwakeRow.alignment = .center
        keepAwakeRow.spacing = 12
        let keepAwakeText = label("Mantener pantalla encendida", size: 14, weight: .medium, color: .white)
        keepAwakeText.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        keepAwakeRow.addArrangedSubview(keepAwakeText)
        keepAwakeRow.addArrangedSubview(keepAwakeToggle)
        keepAwakeToggle.onTintColor = accent
        keepAwakeToggle.addTarget(self, action: #selector(toggleScreenAwake), for: .valueChanged)
        backgroundPanel.addArrangedSubview(keepAwakeRow)
        serverSections.addArrangedSubview(backgroundPanel)

        activitySections.addArrangedSubview(label("NEXORA · UTILIDADES", size: 12, weight: .semibold, color: accent))
        activitySections.addArrangedSubview(label("Estado", size: 33, weight: .bold, color: .label))
        activitySections.addArrangedSubview(label("Información del servidor, solicitudes recibidas y eventos recientes.", size: 14, weight: .regular, color: muted))

        let statusCard = makePanel()
        statusCard.addArrangedSubview(label("ESTADO ACTUAL", size: 12, weight: .semibold, color: muted))
        activityStatusLabel.font = .monospacedSystemFont(ofSize: 18, weight: .semibold)
        statusCard.addArrangedSubview(activityStatusLabel)
        activitySections.addArrangedSubview(statusCard)

        activitySections.addArrangedSubview(section("01", "Resumen"))
        let logs = makePlainPanel()
        logLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        logLabel.textColor = muted
        logLabel.numberOfLines = 0
        logs.addArrangedSubview(logLabel)
        countLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        countLabel.textColor = accent
        logs.addArrangedSubview(countLabel)
        activitySections.addArrangedSubview(logs)

        activitySections.addArrangedSubview(section("02", "Últimas solicitudes"))
        let recentRequests = makePlainPanel()
        recentRequestsLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        recentRequestsLabel.textColor = muted
        recentRequestsLabel.numberOfLines = 0
        recentRequests.addArrangedSubview(recentRequestsLabel)
        activitySections.addArrangedSubview(recentRequests)
        activitySections.addArrangedSubview(label("Historial temporal de las últimas 25 peticiones. Se borra al cerrar la app.", size: 12, weight: .regular, color: muted))
        serverSections.addArrangedSubview(label("Solo en este iPhone • 127.0.0.1:8080 • Sin anuncios", size: 12, weight: .regular, color: muted))
    }

    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        serverSections.isHidden = item.tag != 0
        activitySections.isHidden = item.tag != 1
        scroll.setContentOffset(.zero, animated: false)
    }

    private func label(_ title: String, size: CGFloat, weight: UIFont.Weight, color: UIColor) -> UILabel {
        let output = UILabel()
        output.text = title
        output.textColor = color
        output.font = .systemFont(ofSize: size, weight: weight)
        output.numberOfLines = 0
        return output
    }

    private func section(_ number: String, _ title: String) -> UILabel {
        label("\(number)  /  \(title)", size: 13, weight: .semibold, color: accent)
    }

    private func makePanel() -> UIStackView {
        let panel = UIStackView()
        panel.axis = .vertical
        panel.spacing = 13
        panel.isLayoutMarginsRelativeArrangement = true
        panel.layoutMargins = UIEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        panel.layer.cornerRadius = 20
        panel.clipsToBounds = true

        let effect: UIVisualEffect
        if #available(iOS 26.0, *) {
            effect = UIGlassEffect()
        } else {
            effect = UIBlurEffect(style: .systemThinMaterialDark)
        }
        let glass = UIVisualEffectView(effect: effect)
        glass.translatesAutoresizingMaskIntoConstraints = false
        panel.insertSubview(glass, at: 0)
        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: panel.topAnchor),
            glass.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            glass.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: panel.trailingAnchor)
        ])
        return panel
    }

    /// Las áreas de contenido se mantienen opacas, como recomienda el diseño de Apple.
    /// El material Liquid Glass queda reservado para estado y controles interactivos.
    private func makePlainPanel() -> UIStackView {
        let panel = UIStackView()
        panel.axis = .vertical
        panel.spacing = 13
        panel.isLayoutMarginsRelativeArrangement = true
        panel.layoutMargins = UIEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        panel.layer.cornerRadius = 18
        panel.backgroundColor = UIColor.secondarySystemGroupedBackground
        return panel
    }

    private func makeButton(_ title: String, symbol: String, action: Selector, emphasized: Bool) -> UIButton {
        let button = UIButton(type: .system)
        configureButton(button, title: title, symbol: symbol, emphasized: emphasized)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func configureButton(_ button: UIButton, title: String, symbol: String, emphasized: Bool, tint: UIColor? = nil) {
        var config: UIButton.Configuration
        if #available(iOS 26.0, *) {
            config = emphasized ? .prominentGlass() : .glass()
        } else {
            config = emphasized ? .filled() : .tinted()
        }
        config.title = title
        config.image = UIImage(systemName: symbol)
        config.imagePadding = 10
        config.baseForegroundColor = emphasized ? UIColor.white : (tint ?? UIColor.label)
        if emphasized { config.baseBackgroundColor = tint ?? accent }
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
        config.cornerStyle = .medium
        button.tintColor = tint ?? (emphasized ? accent : UIColor.tertiaryLabel)
        button.configuration = config
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 49).isActive = true
    }

    private func refresh() {
        let hasHTML = FileManager.default.fileExists(atPath: siteDirectory.appendingPathComponent("index.html").path)
        let fileCount = (try? FileManager.default.contentsOfDirectory(atPath: siteDirectory.path).count) ?? 0
        let selected = UserDefaults.standard.string(forKey: "selectedHTMLName") ?? "index.html"
        selectedLabel.text = hasHTML ? "\(selected)  ✓" : "No seleccionaste un HTML"
        resourcesLabel.text = hasHTML ? "\(max(0, fileCount - 1)) recursos adicionales guardados" : "Elegí un archivo desde Archivos"
        statusLabel.text = lastStatus
        statusLabel.textColor = running ? successColor : (starting ? .systemOrange : .white)
        startButton.isEnabled = hasHTML && !running && !starting && !wantsServer
        stopButton.isEnabled = wantsServer || running || starting
        previewButton.isEnabled = hasHTML && !starting
        copyButton.isEnabled = running
        for control in [startButton, stopButton, previewButton, copyButton] {
            control.alpha = control.isEnabled ? 1 : 0.45
        }
        exampleButton.isHidden = hasHTML
        logLabel.text = lastLog
        countLabel.text = "Peticiones: \(requests)"
        activityStatusLabel.text = lastStatus
        activityStatusLabel.textColor = running ? successColor : (starting ? .systemOrange : .label)
        recentRequestsLabel.text = requestHistory.isEmpty ? "Todavía no hay peticiones. Abrí Vista previa para probar el servidor." : requestHistory.joined(separator: "\n\n")
        activityLabel.text = pausedByIOS ? "iOS pausó el servicio · Se reinicia al volver" : (running ? "Escuchando solo en este dispositivo" : "El puerto está cerrado")
        UIApplication.shared.isIdleTimerDisabled = keepAwakeToggle.isOn && (running || starting)
    }

    private func updateServerStatus(_ status: LocalHTTPServer.Status) {
        switch status {
        case .starting:
            running = false
            starting = true
            lastStatus = "INICIANDO…"
        case .running:
            running = true
            starting = false
            pausedByIOS = false
            lastStatus = "● ACTIVO · 8080"
            lastLog = "Servidor escuchando en 127.0.0.1:8080"
            if previewAfterStarting {
                previewAfterStarting = false
                DispatchQueue.main.async { [weak self] in self?.presentPreview() }
            }
        case .stopped:
            running = false
            starting = false
            lastStatus = pausedByIOS ? "Ⅱ PAUSADO POR iOS" : "○ DETENIDO"
        case .failed(let reason):
            previewAfterStarting = false
            running = false
            starting = false
            wantsServer = false
            lastStatus = "✕ ERROR"
            lastLog = reason
        }
        refresh()
    }

    @objc private func startServer() {
        wantsServer = true
        pausedByIOS = false
        starting = true
        requests = 0
        requestHistory.removeAll()
        lastStatus = "INICIANDO…"
        refresh()
        server.start(directory: siteDirectory)
    }

    @objc private func stopServer() {
        // Detener manualmente también desactiva cualquier reinicio automático.
        previewAfterStarting = false
        wantsServer = false
        pausedByIOS = false
        wasBackgrounded = false
        endBackgroundTask()
        running = false
        starting = false
        lastStatus = "○ DETENIDO"
        lastLog = "Servidor terminado manualmente. Conexiones cerradas."
        server.stop()
        refresh()
    }

    @objc private func openPreview() {
        guard FileManager.default.fileExists(atPath: siteDirectory.appendingPathComponent("index.html").path) else { return }
        if running {
            presentPreview()
        } else if !starting {
            previewAfterStarting = true
            startServer()
        }
    }

    private func presentPreview() {
        guard running, presentedViewController == nil else { return }
        let preview = PreviewViewController(onStop: { [weak self] in self?.stopServer() })
        preview.modalPresentationStyle = .fullScreen
        present(preview, animated: true)
    }

    @objc private func copyURL() {
        UIPasteboard.general.string = "http://localhost:8080"
        lastLog = "Dirección copiada"
        refresh()
    }

    @objc private func toggleScreenAwake() {
        UserDefaults.standard.set(keepAwakeToggle.isOn, forKey: "keepScreenOn")
        refresh()
    }

    @objc private func didEnterBackground() {
        guard wantsServer else { return }
        wasBackgrounded = true
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "ServerStarter: finalizar solicitudes") { [weak self] in
            guard let self = self else { return }
            // El sistema está por suspender la app: cerrar con seguridad.
            self.pausedByIOS = true
            self.server.stop()
            self.endBackgroundTask()
        }
    }

    @objc private func willEnterForeground() {
        endBackgroundTask()
        guard wasBackgrounded else { return }
        wasBackgrounded = false
        guard wantsServer else { return }
        // Reabrimos el listener aun si iOS suspendió el proceso sin ejecutar la expiración.
        pausedByIOS = false
        starting = true
        lastStatus = "REANUDANDO…"
        refresh()
        server.start(directory: siteDirectory)
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        let task = backgroundTask
        backgroundTask = .invalid
        UIApplication.shared.endBackgroundTask(task)
    }

    @objc private func selectHTML() {
        importMode = .html
        showPicker(types: [.html], multiple: false)
    }

    @objc private func selectResources() {
        importMode = .resources
        showPicker(types: [.item], multiple: true)
    }

    private func showPicker(types: [UTType], multiple: Bool) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = multiple
        present(picker, animated: true)
    }

    @objc private func importExample() {
        guard let source = Bundle.main.url(forResource: "Demo", withExtension: "html") else {
            lastLog = "HTML de prueba no incluido en la compilación"
            refresh()
            return
        }
        if wantsServer { stopServer() }
        do {
            try Data(contentsOf: source).write(to: siteDirectory.appendingPathComponent("index.html"), options: .atomic)
            UserDefaults.standard.set("Demo.html", forKey: "selectedHTMLName")
            lastLog = "HTML de ejemplo importado. Tocá Iniciar servidor."
        } catch { lastLog = "Error importando ejemplo: \(error.localizedDescription)" }
        refresh()
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if wantsServer { stopServer() }
        var saved = 0
        var errorMessage: String?
        for (index, source) in urls.enumerated() {
            let access = source.startAccessingSecurityScopedResource()
            defer { if access { source.stopAccessingSecurityScopedResource() } }
            let filename: String
            if importMode == .html {
                guard index == 0 else { break }
                filename = "index.html"
            } else {
                filename = source.lastPathComponent
            }
            guard !filename.isEmpty, filename != ".", filename != "..",
                  !filename.contains("/"), !filename.contains("\\") else { continue }
            do {
                let values = try source.resourceValues(forKeys: [.isDirectoryKey])
                if values.isDirectory == true { continue }
                try Data(contentsOf: source).write(to: siteDirectory.appendingPathComponent(filename), options: .atomic)
                if importMode == .html {
                    UserDefaults.standard.set(source.lastPathComponent, forKey: "selectedHTMLName")
                }
                saved += 1
            } catch { errorMessage = error.localizedDescription }
        }
        lastLog = saved > 0 ? "Importados \(saved) archivo(s)" : (errorMessage ?? "No se importaron archivos")
        refresh()
    }
}
