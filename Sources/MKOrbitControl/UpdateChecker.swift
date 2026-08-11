import Foundation
import AppKit

class UpdateChecker {
    static let shared = UpdateChecker()

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.4"
    }
    private let repoOwner = "mks-devx"
    private let repoName = "MK-OrbitControl"
    private let checkInterval: TimeInterval = 86400
    private let lastCheckKey = "MKLastUpdateCheck"

    func checkOnLaunch() {
        let lastCheck = UserDefaults.standard.double(forKey: lastCheckKey)
        let now = Date().timeIntervalSince1970
        if now - lastCheck < checkInterval { return }
        check(isManual: false)
    }

    func checkManually() {
        check(isManual: true)
    }

    private func check(isManual: Bool) {
        let urlString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self, error == nil, let httpResponse = response as? HTTPURLResponse else {
                if isManual {
                    DispatchQueue.main.async { self?.showError() }
                }
                return
            }
            if httpResponse.statusCode == 404 {
                if isManual { DispatchQueue.main.async { self.showNoPublishedRelease() } }
                return
            }
            guard let data, (200..<300).contains(httpResponse.statusCode) else {
                if isManual { DispatchQueue.main.async { self.showError() } }
                return
            }
            self.handleResponse(data, isManual: isManual)
        }.resume()
    }

    private func handleResponse(_ data: Data, isManual: Bool) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String,
              let htmlUrl = json["html_url"] as? String else {
            if isManual { DispatchQueue.main.async { self.showError() } }
            return
        }

        handleVersion(tagName: tagName, url: htmlUrl, isManual: isManual)
    }

    private func handleVersion(tagName: String, url: String, isManual: Bool) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
        let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

        if Self.isNewerVersion(latestVersion, than: currentVersion) {
            DispatchQueue.main.async {
                self.showUpdateAlert(version: latestVersion, url: url)
            }
        } else if isManual {
            DispatchQueue.main.async {
                self.showUpToDate()
            }
        }
    }

    static func isNewerVersion(_ new: String, than current: String) -> Bool {
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

    private func showNoPublishedRelease() {
        let alert = NSAlert()
        alert.messageText = "No Published Release"
        alert.informativeText = "The repository has source tags, but no downloadable GitHub Release is currently published."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
