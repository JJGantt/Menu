import SwiftUI
import UIKit

/// Two-tier image cache: NSCache for instant in-memory hits, URLCache (disk-backed)
/// for survival across app launches. URLCache is wired into a dedicated URLSession
/// so cached responses come back without a network round-trip.
final class RemoteImageCache {
    static let shared = RemoteImageCache()

    private let memory = NSCache<NSString, UIImage>()
    let session: URLSession

    init() {
        memory.countLimit = 500
        let disk = URLCache(
            memoryCapacity:  32 * 1024 * 1024,   // 32 MB RAM (for the URL layer)
            diskCapacity:   256 * 1024 * 1024,   // 256 MB on disk
            diskPath:       "RemoteImageCache"
        )
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = disk
        // Use cache, but revalidate with the server (If-None-Match / ETag).
        // Supabase Storage returns ETags, so unchanged images get a tiny 304 and
        // updated images get fresh bytes.
        cfg.requestCachePolicy = .useProtocolCachePolicy
        session = URLSession(configuration: cfg)
    }

    func image(for url: URL) -> UIImage? { memory.object(forKey: url.absoluteString as NSString) }
    func set(_ image: UIImage, for url: URL) { memory.setObject(image, forKey: url.absoluteString as NSString) }

    /// The image at `url`: from memory, else the network (revalidating the disk copy), else the disk
    /// copy alone. The last step is what works offline: a stale copy needs a revalidation the network
    /// cannot give, and URLSession fails that request rather than fall back to it.
    func load(_ url: URL) async -> UIImage? {
        if let cached = image(for: url) { return cached }
        for policy in [URLRequest.CachePolicy.useProtocolCachePolicy, .returnCacheDataDontLoad] {
            if let fetched = try? await session.data(for: URLRequest(url: url, cachePolicy: policy)),
               let ui = UIImage(data: fetched.0) {
                set(ui, for: url)
                return ui
            }
        }
        return nil
    }

    /// Downloads each image not already on disk, so a page never opened still shows offline.
    func prefetch(_ urls: [URL]) async {
        for url in Set(urls) where session.configuration.urlCache?.cachedResponse(for: URLRequest(url: url)) == nil {
            _ = try? await session.data(for: URLRequest(url: url))
        }
    }
}

/// A dish photo's URL: `menu_dishes.image` names the file, which lives in the public `dishes` bucket.
func dishPhotoURL(_ image: String?) -> URL? {
    guard let image, !image.isEmpty else { return nil }
    return SupabaseClient.publicObjectURL(bucket: "dishes", object: (image as NSString).lastPathComponent)
}

/// A dish photo, drawn by `content` once it has loaded. Nothing is drawn when the dish has none, so
/// a dish without a photo takes no space.
struct DishPhoto<Content: View>: View {
    let url: URL?
    @ViewBuilder let content: (UIImage) -> Content
    @State private var image: UIImage?

    init(_ image: String?, @ViewBuilder content: @escaping (UIImage) -> Content) {
        url = dishPhotoURL(image)
        self.content = content
        if let url, let cached = RemoteImageCache.shared.image(for: url) { _image = State(initialValue: cached) }
    }

    var body: some View {
        if let image {
            content(image)
        } else if let url {
            // A view has to exist for its task to run; this one has no size.
            Color.clear.frame(width: 0, height: 0)
                .task(id: url) { image = await RemoteImageCache.shared.load(url) }
        }
    }
}

struct RemoteImage: View {
    let urlString: String?
    var contentMode: ContentMode = .fit

    @State private var image: UIImage?
    @State private var failed = false

    init(urlString: String?, contentMode: ContentMode = .fit) {
        self.urlString = urlString
        self.contentMode = contentMode
        // Synchronous cache check on init so cache hits render with no flicker.
        if let s = urlString, let url = URL(string: s),
           let cached = RemoteImageCache.shared.image(for: url) {
            _image = State(initialValue: cached)
        }
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if failed || urlString == nil {
                Rectangle().fill(Color.cgBorder.opacity(0.3))
            } else {
                Rectangle().fill(Color.cgBorder.opacity(0.15))
                    .overlay(ProgressView().scaleEffect(0.7))
            }
        }
        .task(id: urlString) { await load() }
    }

    private func load() async {
        guard let s = urlString, let url = URL(string: s) else { failed = true; return }
        if let ui = await RemoteImageCache.shared.load(url) { image = ui } else { failed = true }
    }
}
