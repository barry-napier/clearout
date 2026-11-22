import Foundation

/// "Smart picks": big things the fixed rules do not know, that you may have forgotten.
/// Plain rules choose them and write the reason. The AI has no say in this.
enum Suggestions {
    /// Their children can be picks.
    static let places = ["", "Developer", "Downloads", "Movies", "Music", "Pictures"]
    static let minimumSize: Int64 = 50_000_000
    static let limit = 24

    private static let untouchedDays = 30
    private static let archives: Set<String> = ["zip", "gz", "tgz", "tar", "7z", "rar", "xz"]

    static func reason(name: String, isFolder: Bool, lastChanged: Double, folderNames: Set<String>, now: Date) -> String? {
        let file = name as NSString
        if !isFolder, archives.contains(file.pathExtension.lowercased()) {
            let base = (file.deletingPathExtension as NSString)
            let unzipped = base.pathExtension.lowercased() == "tar" ? base.deletingPathExtension : base as String
            if folderNames.contains(unzipped) {
                return "A folder with the same name is next to it. You may not need both."
            }
        }
        let days = Int((now.timeIntervalSince1970 - lastChanged / 1000) / 86400)
        guard days >= untouchedDays else { return nil }
        return "Not changed for \(age(days))."
    }

    static func age(_ days: Int) -> String {
        if days >= 730 { return "\(days / 365) years" }
        if days >= 365 { return "over a year" }
        if days >= 60 { return "\(days / 30) months" }
        return "a month"
    }
}
