import Foundation

// Filesystem boundary for pure detection/classifier fixtures, never production.
enum GORResources {
    static func vendorPath(_ path: String) -> String {
        return "/missing/" + path
    }
}
