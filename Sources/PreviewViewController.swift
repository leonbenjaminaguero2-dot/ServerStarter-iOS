import UIKit
import WebKit

final class PreviewViewController: UIViewController {
    private let onStop: () -> Void
    private let webView = WKWebView(frame: .zero)

    init(onStop: @escaping () -> Void) {
        self.onStop = onStop
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no soportado") }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .systemBackground
        let toolbarEffect: UIVisualEffect
        if #available(iOS 26.0, *) {
            toolbarEffect = UIGlassEffect()
        } else {
            toolbarEffect = UIBlurEffect(style: .systemThinMaterialDark)
        }
        let toolbar = UIVisualEffectView(effect: toolbarEffect)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)

        let address = UILabel()
        address.text = "localhost:8080"
        address.textColor = .white
        address.font = .monospacedSystemFont(ofSize: 14, weight: .semibold)
        address.translatesAutoresizingMaskIntoConstraints = false
        toolbar.contentView.addSubview(address)

        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        close.tintColor = .white
        close.addTarget(self, action: #selector(closePreview), for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false
        toolbar.contentView.addSubview(close)

        let reload = UIButton(type: .system)
        reload.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        reload.tintColor = .white
        reload.addTarget(self, action: #selector(reloadPage), for: .touchUpInside)
        reload.translatesAutoresizingMaskIntoConstraints = false
        toolbar.contentView.addSubview(reload)

        let stop = UIButton(type: .system)
        stop.setImage(UIImage(systemName: "stop.circle.fill"), for: .normal)
        stop.tintColor = .systemRed
        stop.addTarget(self, action: #selector(stopAndClose), for: .touchUpInside)
        stop.translatesAutoresizingMaskIntoConstraints = false
        toolbar.contentView.addSubview(stop)

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 56),
            close.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 17),
            close.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            address.leadingAnchor.constraint(equalTo: close.trailingAnchor, constant: 12),
            address.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            stop.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -17),
            stop.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            reload.trailingAnchor.constraint(equalTo: stop.leadingAnchor, constant: -17),
            reload.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            address.trailingAnchor.constraint(lessThanOrEqualTo: reload.leadingAnchor, constant: -12),
            webView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        reloadPage()
    }

    @objc private func closePreview() { dismiss(animated: true) }
    @objc private func stopAndClose() { onStop(); dismiss(animated: true) }
    @objc private func reloadPage() {
        guard let url = URL(string: "http://localhost:8080/") else { return }
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
    }
}
