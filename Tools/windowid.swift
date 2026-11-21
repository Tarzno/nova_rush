// Prints the CGWindowID of the first on-screen window owned by the given
// process name. Usage: swift Tools/windowid.swift NovaRush
import CoreGraphics
import Foundation

let name = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "NovaRush"
guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
        as? [[String: Any]] else { exit(1) }
for w in list {
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    if owner.contains(name), let id = w[kCGWindowNumber as String] as? Int {
        print(id)
        exit(0)
    }
}
exit(1)
