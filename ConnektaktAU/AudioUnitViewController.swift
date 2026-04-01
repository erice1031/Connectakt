import CoreAudioKit
import SwiftUI

@MainActor
public final class AudioUnitViewController: AUViewController, AUAudioUnitFactory {
    private var audioUnitInstance: ConnectaktAudioUnit?
    private var hostingController: UIHostingController<ConnectaktAUView>?

    public override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
    }

    nonisolated public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        try DispatchQueue.main.sync {
            let unit = try ConnectaktAudioUnit(componentDescription: componentDescription, options: [])
            audioUnitInstance = unit
            return unit
        }
    }

    private func configureView() {
        let host = UIHostingController(rootView: ConnectaktAUView())
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        hostingController = host
    }
}
