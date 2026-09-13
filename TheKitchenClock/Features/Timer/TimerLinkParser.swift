import Foundation

enum TimerLinkParser {
    enum Error: Swift.Error, Equatable {
        case invalidScheme
        case invalidRoute
        case invalidParameters
    }

    static func parse(_ url: URL) throws(Error) -> TimerLinkRequest {
        guard url.scheme?.lowercased() == "kitchenclock" else {
            throw .invalidScheme
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host?.lowercased() == "timer",
              components.path.isEmpty,
              components.fragment == nil else {
            throw .invalidRoute
        }

        guard let queryItems = components.queryItems,
              queryItems.count == 1,
              let queryItem = queryItems.first,
              queryItem.name == "seconds",
              let secondsValue = queryItem.value,
              secondsValue.utf8.allSatisfy({ (48...57).contains($0) }),
              let seconds = Int64(secondsValue),
              (1...(99 * 3_600 + 59 * 60 + 59)).contains(seconds) else {
            throw .invalidParameters
        }

        return TimerLinkRequest(duration: .seconds(seconds))
    }
}
