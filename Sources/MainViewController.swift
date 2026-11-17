import UIKit
import UniformTypeIdentifiers

/// ServerStarter: interfaz nativa. Liquid Glass real en iOS 26+.
/// No declara modos de fondo falsos (audio, ubicación, VoIP).
final class MainViewController: UIViewController, UIDocumentPickerDelegate, UITabBarDelegate, UITextViewDelegate {
    private enum ImportMode { case html, resources }

    private let server = LocalHTTPServer()
    private let accent = UIColor.systemCyan
    private let successColor = UIColor.systemGreen
    private let dangerColor = UIColor.systemRed
    private let muted = UIColor.secondaryLabel
    private let background = UIColor(red: 0.015, green: 0.055, blue: 0.075, alpha: 1)
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
    private let editorSections = UIStackView()
    private let settingsSections = UIStackView()
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
    private var serverStartedAt: Date?
    private var uptimeTimer: Timer?
    private let exampleButton = UIButton(type: .system)
    private let editorTextView = UITextView()

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
        uptimeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        keepAwakeToggle.isOn = UserDefaults.standard.bool(forKey: "keepScreenOn")
        refresh()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        uptimeTimer?.invalidate()
        server.stop()
    }

    private func configureInterface() {
        scroll.alwaysBounceVertical = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)

        // Navegación inferior con las tres áreas visibles en la referencia.
        navigationBar.translatesAutoresizingMaskIntoConstraints = false
        navigationBar.delegate = self
        navigationBar.items = [
            UITabBarItem(title: "Servidor", image: UIImage(systemName: "server.rack"), tag: 0),
            UITabBarItem(title: "Editor", image: UIImage(systemName: "chevron.left.forwardslash.chevron.right"), tag: 1),
            UITabBarItem(title: "Ajustes", image: UIImage(systemName: "gearshape"), tag: 2)
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

        for sectionStack in [serverSections, editorSections, settingsSections] {
            sectionStack.axis = .vertical
            sectionStack.spacing = 17
            content.addArrangedSubview(sectionStack)
        }
        editorSections.isHidden = true
        settingsSections.isHidden = true

        serverSections.addArrangedSubview(label("ServerStarter", size: 33, weight: .bold, color: .label))
        serverSections.addArrangedSubview(label("Inicia un servidor local en tu iPhone.", size: 15, weight: .regular, color: muted))

        let statusPanel = makePanel()
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

        serverSections.addArrangedSubview(section("", "Archivos"))
        let filePanel = makePlainPanel()
        selectedLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        selectedLabel.textColor = .white
        selectedLabel.numberOfLines = 2
        filePanel.addArrangedSubview(selectedLabel)
        resourcesLabel.font = .systemFont(ofSize: 13)
        resourcesLabel.textColor = muted
        resourcesLabel.numberOfLines = 0
        filePanel.addArrangedSubview(resourcesLabel)
        let fileActions = UIStackView()
        fileActions.axis = .horizontal
        fileActions.spacing = 10
        let chooseHTML = makeButton("Elegir HTML", symbol: "folder", action: #selector(selectHTML), emphasized: false)
        let addResources = makeButton("Añadir recursos", symbol: "square.stack.3d.up", action: #selector(selectResources), emphasized: false)
        chooseHTML.titleLabel?.adjustsFontSizeToFitWidth = true
        addResources.titleLabel?.adjustsFontSizeToFitWidth = true
        fileActions.addArrangedSubview(chooseHTML)
        fileActions.addArrangedSubview(addResources)
        filePanel.addArrangedSubview(fileActions)
        exampleButton.setTitle("Usar página de ejemplo", for: .normal)
        exampleButton.tintColor = accent
        exampleButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        exampleButton.contentHorizontalAlignment = .left
        exampleButton.addTarget(self, action: #selector(importExample), for: .touchUpInside)
        filePanel.addArrangedSubview(exampleButton)
        serverSections.addArrangedSubview(filePanel)

        serverSections.addArrangedSubview(section("", "Control del servidor"))
        configureButton(startButton, title: "Iniciar servidor", symbol: "play.fill", emphasized: true, tint: successColor)
        startButton.addTarget(self, action: #selector(startServer), for: .touchUpInside)
        configureButton(stopButton, title: "Terminar servidor", symbol: "stop.fill", emphasized: true, tint: dangerColor)
        stopButton.addTarget(self, action: #selector(stopServer), for: .touchUpInside)
        let serverActions = UIStackView()
        serverActions.axis = .horizontal
        serverActions.spacing = 10
        serverActions.distribution = .fillEqually
        serverActions.addArrangedSubview(startButton)
        serverActions.addArrangedSubview(stopButton)
        serverSections.addArrangedSubview(serverActions)

        serverSections.addArrangedSubview(section("", "Página web"))
        configureButton(previewButton, title: "Vista previa", symbol: "safari.fill", emphasized: true, tint: accent)
        previewButton.addTarget(self, action: #selector(openPreview), for: .touchUpInside)
        previewButton.setTitle("Vista previa\nAbrir http://localhost:8080", for: .normal)
        serverSections.addArrangedSubview(previewButton)

        // Editor real del index.html guardado en la carpeta servida.
        editorSections.addArrangedSubview(label("Editor", size: 33, weight: .bold, color: .label))
        editorSections.addArrangedSubview(label("Editá el HTML del sitio y guardalo en index.html.", size: 14, weight: .regular, color: muted))
        editorTextView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        editorTextView.textColor = .label
        editorTextView.backgroundColor = .secondarySystemGroupedBackground
        editorTextView.layer.cornerRadius = 16
        editorTextView.textContainerInset = UIEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)
        editorTextView.autocapitalizationType = .none
        editorTextView.autocorrectionType = .no
        editorTextView.spellCheckingType = .no
        editorTextView.delegate = self
        editorTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true
        editorSections.addArrangedSubview(editorTextView)
        editorSections.addArrangedSubview(makeButton("Guardar index.html", symbol: "square.and.arrow.down", action: #selector(saveEditor), emphasized: true))
        editorSections.addArrangedSubview(makeButton("Abrir vista previa", symbol: "safari", action: #selector(openPreview), emphasized: false))

        settingsSections.addArrangedSubview(label("Ajustes", size: 33, weight: .bold, color: .label))
        settingsSections.addArrangedSubview(label("Opciones del servidor local.", size: 14, weight: .regular, color: muted))
        settingsSections.addArrangedSubview(section("", "Pantalla"))
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
        settingsSections.addArrangedSubview(backgroundPanel)

        settingsSections.addArrangedSubview(section("", "Actividad reciente"))

        let statusCard = makePanel()
        statusCard.addArrangedSubview(label("ESTADO ACTUAL", size: 12, weight: .semibold, color: muted))
        activityStatusLabel.font = .monospacedSystemFont(ofSize: 18, weight: .semibold)
        statusCard.addArrangedSubview(activityStatusLabel)
        settingsSections.addArrangedSubview(statusCard)

        settingsSections.addArrangedSubview(section("", "Resumen"))
        let logs = makePlainPanel()
        logLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        logLabel.textColor = muted
        logLabel.numberOfLines = 0
        logs.addArrangedSubview(logLabel)
        countLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        countLabel.textColor = accent
        logs.addArrangedSubview(countLabel)
        settingsSections.addArrangedSubview(logs)

        settingsSections.addArrangedSubview(section("", "Últimas solicitudes"))
        let recentRequests = makePlainPanel()
        recentRequestsLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        recentRequestsLabel.textColor = muted
        recentRequestsLabel.numberOfLines = 0
        recentRequests.addArrangedSubview(recentRequestsLabel)
        settingsSections.addArrangedSubview(recentRequests)
        settingsSections.addArrangedSubview(label("Historial temporal de las últimas 25 peticiones. Se borra al cerrar la app.", size: 12, weight: .regular, color: muted))
        settingsSections.addArrangedSubview(makeButton("Copiar URL del servidor", symbol: "link", action: #selector(copyURL), emphasized: false))
        settingsSections.addArrangedSubview(label("iOS puede pausar el servidor al suspender la app. Mantén ServerStarter visible para mayor continuidad.", size: 12, weight: .regular, color: muted))
    }

    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        serverSections.isHidden = item.tag != 0
        editorSections.isHidden = item.tag != 1
        settingsSections.isHidden = item.tag != 2
        scroll.setContentOffset(.zero, animated: false)
        if item.tag == 1 { loadEditorIfNeeded() }
    }

    private func loadEditorIfNeeded() {
        guard !editorTextView.isFirstResponder else { return }
        guard let html = try? String(contentsOf: siteDirectory.appendingPathComponent("index.html"), encoding: .utf8) else {
            editorTextView.text = "<!doctype html>\n<html lang=\"es\">\n<head>\n  <meta charset=\"utf-8\">\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n  <title>Mi sitio</title>\n</head>\n<body>\n  <h1>Mi sitio local</h1>\n  <p>Tu página ya está lista para editar.</p>\n</body>\n</html>"
            return
        }
        editorTextView.text = html
    }

    @objc private func saveEditor() {
        do {
            try editorTextView.text.write(to: siteDirectory.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
            UserDefaults.standard.set("index.html", forKey: "selectedHTMLName")
            lastLog = "index.html guardado"
            refresh()
        } catch {
            lastLog = "No se pudo guardar index.html: \(error.localizedDescription)"
            refresh()
        }
    }

    private func label(_ title: String, size: CGFloat, weight: UIFont.Weight, color: UIColor) -> UILabel {
        let output = UILabel()
        output.text = title
        output.textColor = color
        output.font = .systemFont(ofSize: size, weight: weight)
        output.numberOfLines = 0
        return output
    }

    private func section(_ number: String, _ title: String) -> UIView {
        let icon: String
        switch title {
        case "Archivos": icon = "folder"
        case "Control del servidor": icon = "server.rack"
        case "Página web": icon = "globe"
        case "Pantalla": icon = "display"
        case "Actividad reciente", "Resumen": icon = "chart.bar"
        default: icon = "list.bullet"
        }
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 9
        let image = UIImageView(image: UIImage(systemName: icon))
        image.tintColor = accent
        image.contentMode = .scaleAspectFit
        image.widthAnchor.constraint(equalToConstant: 22).isActive = true
        image.heightAnchor.constraint(equalToConstant: 22).isActive = true
        row.addArrangedSubview(image)
        row.addArrangedSubview(label(title, size: 18, weight: .semibold, color: .label))
        return row
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
        selectedLabel.text = hasHTML ? "\(selected)  ›" : "No seleccionaste un HTML"
        let htmlURL = siteDirectory.appendingPathComponent("index.html")
        let attributes = try? FileManager.default.attributesOfItem(atPath: htmlURL.path)
        let bytes = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        let fileSize = bytes < 1024 ? "\(bytes) B" : String(format: "%.1f KB", Double(bytes) / 1024)
        resourcesLabel.text = hasHTML ? "\(fileSize) · \(max(0, fileCount - 1)) recursos" : "Elegí un archivo desde Archivos"
        statusLabel.text = lastStatus
        statusLabel.textColor = running ? successColor : (starting ? .systemOrange : .white)
        startButton.isEnabled = hasHTML && !running && !starting && !wantsServer
        stopButton.isEnabled = wantsServer || running || starting
        previewButton.isEnabled = hasHTML && !starting
        for control in [startButton, stopButton, previewButton] {
            control.alpha = control.isEnabled ? 1 : 0.45
        }
        exampleButton.isHidden = hasHTML
        logLabel.text = lastLog
        countLabel.text = "Peticiones: \(requests)"
        activityStatusLabel.text = lastStatus
        activityStatusLabel.textColor = running ? successColor : (starting ? .systemOrange : .label)
        recentRequestsLabel.text = requestHistory.isEmpty ? "Todavía no hay peticiones. Abrí Vista previa para probar el servidor." : requestHistory.joined(separator: "\n\n")
        activityLabel.text = pausedByIOS ? "iOS pausó el servicio · Se reinicia al volver" : (running ? "Escuchando solo en este dispositivo" : "El puerto está cerrado")
        if running, let startedAt = serverStartedAt {
            let elapsed = max(0, Int(Date().timeIntervalSince(startedAt)))
            activityLabel.text = String(format: "%02d:%02d:%02d activo · Solo en este iPhone", elapsed / 3600, (elapsed % 3600) / 60, elapsed % 60)
        }
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
            if serverStartedAt == nil { serverStartedAt = Date() }
            lastStatus = "● Servidor activo"
            lastLog = "Servidor escuchando en 127.0.0.1:8080"
            if previewAfterStarting {
                previewAfterStarting = false
                DispatchQueue.main.async { [weak self] in self?.presentPreview() }
            }
        case .stopped:
            running = false
            starting = false
            serverStartedAt = nil
            lastStatus = pausedByIOS ? "Ⅱ PAUSADO POR iOS" : "○ DETENIDO"
        case .failed(let reason):
            previewAfterStarting = false
            running = false
            starting = false
            wantsServer = false
            serverStartedAt = nil
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
