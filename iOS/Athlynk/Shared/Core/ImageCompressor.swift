//
//  ImageCompressor.swift
//  Downscale + JPEG-encode picked photos before upload so we never push
//  full-resolution camera files over the wire. The backend re-encodes to WebP;
//  this just keeps the request small.
//

import UIKit

enum ImageCompressor {
    /// Resize so the longest side ≤ `maxDim`, then JPEG-encode at `quality`.
    /// Returns the original bytes unchanged if decoding fails.
    static func jpeg(_ data: Data, maxDim: CGFloat = 1600, quality: CGFloat = 0.7) -> Data {
        guard let img = UIImage(data: data) else { return data }
        let longest = max(img.size.width, img.size.height)
        let scale = longest > maxDim ? maxDim / longest : 1
        let target = CGSize(width: img.size.width * scale, height: img.size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1   // target points == pixels; we sized in pixels already
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            img.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality) ?? data
    }
}
