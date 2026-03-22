import AVFoundation
import Foundation

/// Serves a local WebVTT file as a subtitle track for HLS playback.
/// Uses a custom URL scheme so AVAssetResourceLoaderDelegate receives requests.
/// Intercepts the master playlist to add a subtitle reference, then serves the VTT when requested.
final class VTTResourceLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    static let scheme = "youflex"
    static let vttPathPrefix = "/vtt/"

    private let realBaseURL: URL
    private let localVTTURL: URL?
    private let queue = DispatchQueue(label: "com.youflex.vttresourceloader")

    init(realBaseURL: URL, localVTTURL: URL?) {
        self.realBaseURL = realBaseURL
        self.localVTTURL = localVTTURL
    }

    /// Builds a custom URL that will route through this loader.
    static func customURL(realStreamURL: URL, contentId: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "load"
        components.path = "/\(contentId)"
        components.queryItems = [URLQueryItem(name: "url", value: realStreamURL.absoluteString)]
        return components.url
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let url = loadingRequest.request.url else { return false }
        guard url.scheme == Self.scheme else { return false }

        queue.async { [weak self] in
            self?.handleRequest(loadingRequest, url: url)
        }
        return true
    }

    private func handleRequest(_ request: AVAssetResourceLoadingRequest, url: URL) {
        if url.path.hasPrefix(Self.vttPathPrefix) {
            serveVTT(request)
            return
        }
        if url.path.hasPrefix("/subs/") {
            serveSubtitlePlaylist(request)
            return
        }
        if url.host == "load", let streamURL = streamURL(from: url) {
            if isMasterPlaylistRequest(request, url: url) {
                serveModifiedMasterPlaylist(request, realStreamURL: streamURL)
            } else {
                redirect(request, to: streamURL)
            }
            return
        }
        request.finishLoading(with: NSError(domain: NSURLErrorDomain, code: NSURLErrorUnsupportedURL, userInfo: nil))
    }

    private func streamURL(from url: URL) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let urlItem = components.queryItems?.first(where: { $0.name == "url" }),
              let urlString = urlItem.value,
              let streamURL = URL(string: urlString) else {
            return nil
        }
        return streamURL
    }

    private func isMasterPlaylistRequest(_ request: AVAssetResourceLoadingRequest, url: URL) -> Bool {
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = path.split(separator: "/")
        return components.count <= 1 && !path.contains(".")
    }

    private func redirect(_ request: AVAssetResourceLoadingRequest, to streamURL: URL) {
        let origURL = request.request.url!
        let origPath = origURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let base = streamURL.deletingLastPathComponent()
        let targetURL = URL(string: origPath, relativeTo: base)?.absoluteURL ?? base.appendingPathComponent(origPath)
        let redirectReq = URLRequest(url: targetURL)
        request.redirect = redirectReq
        let response = HTTPURLResponse(
            url: origURL,
            statusCode: 302,
            httpVersion: nil,
            headerFields: ["Location": targetURL.absoluteString]
        )
        request.response = response
        request.finishLoading()
    }

    private func serveModifiedMasterPlaylist(_ request: AVAssetResourceLoadingRequest, realStreamURL: URL) {
        let session = URLSession.shared
        let task = session.dataTask(with: realStreamURL) { [weak self] data, _, error in
            guard let self else { return }
            if let error {
                request.finishLoading(with: error)
                return
            }
            guard let data, var text = String(data: data, encoding: .utf8) else {
                request.finishLoading(with: NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotDecodeContentData, userInfo: nil))
                return
            }
            if let vttURL = self.localVTTURL, FileManager.default.fileExists(atPath: vttURL.path) {
                let subPlaylistURL = URL(string: "\(Self.scheme)://host/subs/\(UUID().uuidString).m3u8")!
                text = self.injectSubtitleIntoMasterPlaylist(text, subtitlePlaylistURL: subPlaylistURL)
            }
            if let response = HTTPURLResponse(
                url: request.request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/vnd.apple.mpegurl"]
            ) {
                request.response = response
            }
            request.dataRequest?.respond(with: text.data(using: .utf8)!)
            request.finishLoading()
        }
        task.resume()
    }

    private func injectSubtitleIntoMasterPlaylist(_ playlist: String, subtitlePlaylistURL: URL) -> String {
        var lines = playlist.components(separatedBy: "\n")
        var i = 0
        var insertedMedia = false
        while i < lines.count {
            if lines[i].hasPrefix("#EXT-X-STREAM-INF:") {
                if !lines[i].contains("SUBTITLES=") {
                    lines[i] = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
                    if lines[i].hasSuffix(",") {
                        lines[i] += "SUBTITLES=\"subs\""
                    } else {
                        lines[i] += ",SUBTITLES=\"subs\""
                    }
                }
            }
            if !insertedMedia, lines[i].hasPrefix("#EXT-X-MEDIA:") {
                let media = "#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"subs\",LANGUAGE=\"en\",NAME=\"English\",AUTOSELECT=YES,DEFAULT=YES,URI=\"\(subtitlePlaylistURL.absoluteString)\""
                lines.insert(media, at: i)
                i += 1
                insertedMedia = true
            }
            i += 1
        }
        if !insertedMedia {
            let media = "#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"subs\",LANGUAGE=\"en\",NAME=\"English\",AUTOSELECT=YES,DEFAULT=YES,URI=\"\(subtitlePlaylistURL.absoluteString)\""
            lines.insert(media, at: max(0, lines.count - 1))
        }
        return lines.joined(separator: "\n")
    }

    private func serveSubtitlePlaylist(_ request: AVAssetResourceLoadingRequest) {
        guard let vttURL = localVTTURL, FileManager.default.fileExists(atPath: vttURL.path) else {
            request.finishLoading(with: NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist, userInfo: nil))
            return
        }
        let vttSegmentURL = URL(string: "\(Self.scheme)://host\(Self.vttPathPrefix)segment.vtt")!
        let duration: Int
        if let content = try? String(contentsOf: vttURL), let last = content.split(separator: "\n").last(where: { $0.contains("-->") }) {
            let parts = last.split(separator: " ")
            if parts.count >= 2, let end = parts.last?.split(separator: ".").first {
                let t = end.split(separator: ":")
                if t.count >= 3 {
                    let h = Int(t[0]) ?? 0, m = Int(t[1]) ?? 0, s = Int(t[2]) ?? 0
                    duration = max(1, h * 3600 + m * 60 + s)
                } else {
                    duration = 3600
                }
            } else {
                duration = 3600
            }
        } else {
            duration = 3600
        }
        let m3u8 = """
        #EXTM3U
        #EXT-X-TARGETDURATION:\(duration)
        #EXT-X-VERSION:3
        #EXT-X-MEDIA-SEQUENCE:0
        #EXT-X-PLAYLIST-TYPE:VOD
        #EXTINF:\(duration).0,
        \(vttSegmentURL.absoluteString)
        #EXT-X-ENDLIST
        """
        if let response = HTTPURLResponse(
            url: request.request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/vnd.apple.mpegurl"]
        ) {
            request.response = response
        }
        request.dataRequest?.respond(with: m3u8.data(using: .utf8)!)
        request.finishLoading()
    }

    private func serveVTT(_ request: AVAssetResourceLoadingRequest) {
        guard let vttURL = localVTTURL, FileManager.default.fileExists(atPath: vttURL.path) else {
            request.finishLoading(with: NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist, userInfo: nil))
            return
        }
        do {
            let data = try Data(contentsOf: vttURL)
            if let response = HTTPURLResponse(
                url: request.request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/vtt"]
            ) {
                request.response = response
            }
            request.dataRequest?.respond(with: data)
            request.finishLoading()
        } catch {
            request.finishLoading(with: error)
        }
    }
}
