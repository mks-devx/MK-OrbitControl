import Foundation
import AppKit

class UpdateChecker {
    static let shared = UpdateChecker()

    private let currentVersion = "1.1"
    private let repoOwner = "mks-devx"
    private let repoName = "MK-OrbitControl"
    private let checkInterval: TimeInterval = 86400 // Check once per day
    private let lastCheckKey = "MKLastUpdateCheck"

    func checkOnLaunch() {
        let lastCheck = UserDefaults.standard.double(forKey: lastCheckKey)
        let now = Date().timeIntervalSince1970
        if now - lastCheck < checkInterval { return }

        check()
    }

    func check() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)

        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self, let data, error == nil else { return }
            self.handleResponse(data)
        }.resume()
    }

    private func handleResponse(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String,
              let htmlUrl = json["html_url"] as? String else { return }

        let latestVersion = tagName.replacingOccurrences(of: "v", with: "")
        if latestVersion > currentVersion {
            DispatchQueue.main.async {
                self.showUpdateAlert(version: latestVersion, url: htmlUrl)
            }
        }
    }

    private func showUpdateAlert(version: String, url: String) {
        let alert = NSAlert()
        alert.messageText = "MK-OrbitControl Update Available"
        alert.informativeText = "Version \(version) is available. You have version \(currentVersion)."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let downloadURL = URL(string: url) {
                NSWorkspace.shared.open(downloadURL)
            }
        }
    }
}
