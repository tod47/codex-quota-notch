import Foundation

public protocol SecretStore: AnyObject {
    func read(key: String) throws -> String?
    func write(_ value: String, key: String) throws
    func delete(key: String) throws
}
