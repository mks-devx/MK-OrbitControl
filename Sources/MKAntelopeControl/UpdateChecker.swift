import Foundation
import AppKit

class UpdateChecker {
    static let shared = UpdateChecker()

    private let currentVersion = "1.1"
    private let repoOwner = "mks-devx"
    private let repoName = "MK-OrbitControl"
    private let checkInterval: TimeInterval = 86400
    private let lastCheckKey = "MKLastUpdateCheck"
    private var isManualCheck = false

    func checkOnLaunch() {
        let lastCheck = UserDefaults.standard.double(forKey: lastCheckKey)
        let now = Date().timeIntervalSince1970
        if now - lastCheck < checkInterval { return }
        isManualCheck = false
        check()
    }

    func checkManually() {
        isManualCheck = true
        check()
    }

    private func check() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)

        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self, let data, error == nil else {
                if self?.isManualCheck == true {
                    DispatchQueue.main.async { self?.showError() }
                }
                return
            }
            self.handleResponse(data)
        }.resume()
    }

    private func handleResponse(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String,
              let htmlUrl = json["html_url"] as? String else { return }

        let latestVersion = tagName.replacingOccurrences(of: "v", with: "")

        if isNewerVersion(latestVersion, than: currentVersion) {
            DispatchQueue.main.async {
                self.showUpdateAlert(version: latestVersion, url: htmlUrl)
            }
        } else if isManualCheck {
            DispatchQueue.main.async {
                self.showUpToDate()
            }
        }
    }

    private func isNewerVersion(_ new: String, than current: String) -> Bool {
        let newParts = new.split(separator: ".").compactMap { Int($0) }
        let curParts = current.split(separator: ".").compactMap { Int($0) }
        let count = max(newParts.count, curParts.count)
        for i in 0..<count {
            let n = i < newParts.count ? newParts[i] : 0
            let c = i < curParts.count ? curParts[i] : 0
            if n > c { return true }
            if n < c { return false }
        }
        return false
    }

    private func showUpdateAlert(version: String, url: String) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "MK-OrbitControl v\(version) is available. You have v\(currentVersion)."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            if let downloadURL = URL(string: url) {
                NSWorkspace.shared.open(downloadURL)
            }
        }
    }

    private func showUpToDate() {
        let alert = NSAlert()
        alert.messageText = "You're up to date!"
        alert.informativeText = "MK-OrbitControl v\(currentVersion) is the latest version."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showError() {
        let alert = NSAlert()
        alert.messageText = "Update Check Failed"
        alert.informativeText = "Could not reach GitHub. Check your internet connection."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
