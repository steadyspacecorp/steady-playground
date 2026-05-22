import Foundation

enum TokenStore {
    private static let key = "SteadyAccessToken"

    static var token: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set {
            if let v = newValue, !v.isEmpty {
                UserDefaults.standard.set(v, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}
