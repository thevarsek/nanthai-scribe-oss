import Foundation

/// Only explicit deletion enters the bin; history retention still removes untouched dictations directly.
public enum RecentlyDeleted {
    public static let retention: TimeInterval = 30 * 86_400
    public static func isExpired(_ deletedAt: Date?, now: Date = .now) -> Bool {
        deletedAt.map { now.timeIntervalSince($0) >= retention } ?? false
    }
}
