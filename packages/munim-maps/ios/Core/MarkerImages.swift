import UIKit

// MARK: - Marker images

enum MarkerImages {
  private static let cache = NSCache<NSString, UIImage>()

  /// The image for an `avatar`, `image`, `label` or `dot` marker. `photo` is
  /// the loaded picture (nil while loading or for styles without one).
  static func image(for marker: MunimMarker, photo: UIImage?, scale: CGFloat) -> UIImage? {
    let key = cacheKey(marker, hasPhoto: photo != nil) as NSString
    if let cached = cache.object(forKey: key) { return cached }
    let image: UIImage?
    switch marker.style {
    case .avatar: image = avatar(marker, photo: photo, scale: scale)
    case .image: image = picture(marker, photo: photo, scale: scale)
    case .label: image = label(marker, scale: scale)
    case .dot: image = dot(marker, scale: scale)
    case .pin, .marker: image = nil
    }
    if let image { cache.setObject(image, forKey: key) }
    return image
  }

  private static func cacheKey(_ m: MunimMarker, hasPhoto: Bool) -> String {
    let badges = m.badges.map { "\($0.text)/\($0.position.stringValue)/\($0.color)/\($0.textColor)" }
      .joined(separator: ";")
    return [m.style.stringValue, m.imageUri, "\(hasPhoto)", "\(m.imageSize)", m.color,
            m.borderColor, "\(m.borderWidth)", badges, m.title].joined(separator: "|")
  }

  private static func renderer(_ size: CGSize, _ scale: CGFloat) -> UIGraphicsImageRenderer {
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    format.opaque = false
    return UIGraphicsImageRenderer(size: size, format: format)
  }

  private static func avatar(_ m: MunimMarker, photo: UIImage?, scale: CGFloat) -> UIImage {
    let d = CGFloat(m.imageSize > 0 ? m.imageSize : 44)
    let pad: CGFloat = 8 // room for corner badges
    let size = CGSize(width: d + pad * 2, height: d + pad * 2)
    return renderer(size, scale).image { context in
      let cg = context.cgContext
      let circle = CGRect(x: pad, y: pad, width: d, height: d)
      cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: UIColor(white: 0, alpha: 0.25).cgColor)
      (UIColor(mapModelHex: m.borderColor) ?? .white).setFill()
      cg.fillEllipse(in: circle)
      cg.setShadow(offset: .zero, blur: 0, color: nil)
      let ring = CGFloat(max(0, m.borderWidth))
      let inner = circle.insetBy(dx: ring, dy: ring)
      cg.saveGState()
      cg.addEllipse(in: inner)
      cg.clip()
      UIColor(white: 0.88, alpha: 1).setFill()
      cg.fill(inner)
      if let photo { drawAspectFill(photo, in: inner) }
      cg.restoreGState()
      drawBadges(m.badges, around: circle, in: cg)
    }
  }

  private static func picture(_ m: MunimMarker, photo: UIImage?, scale: CGFloat) -> UIImage? {
    guard let photo else { return nil }
    let w = CGFloat(m.imageSize > 0 ? m.imageSize : photo.size.width)
    let h = w * photo.size.height / max(1, photo.size.width)
    let pad: CGFloat = m.badges.isEmpty ? 0 : 8
    return renderer(CGSize(width: w + pad * 2, height: h + pad * 2), scale).image { context in
      let rect = CGRect(x: pad, y: pad, width: w, height: h)
      photo.draw(in: rect)
      drawBadges(m.badges, around: rect, in: context.cgContext)
    }
  }

  private static func label(_ m: MunimMarker, scale: CGFloat) -> UIImage {
    let font = UIFont.systemFont(ofSize: 13, weight: .semibold)
    let text = (m.title.isEmpty ? " " : m.title) as NSString
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
    let textSize = text.size(withAttributes: attributes)
    let size = CGSize(width: ceil(textSize.width) + 20, height: 26)
    return renderer(size, scale).image { _ in
      let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
      (UIColor(mapModelHex: m.color) ?? UIColor(white: 0.1, alpha: 0.9)).setFill()
      UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).fill()
      text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
                withAttributes: attributes)
    }
  }

  private static func dot(_ m: MunimMarker, scale: CGFloat) -> UIImage {
    let d = CGFloat(m.imageSize > 0 ? m.imageSize : 14)
    return renderer(CGSize(width: d, height: d), scale).image { context in
      let rect = CGRect(x: 0, y: 0, width: d, height: d)
      (UIColor(mapModelHex: m.borderColor) ?? .white).setFill()
      context.cgContext.fillEllipse(in: rect)
      let ring = CGFloat(m.borderWidth > 0 ? m.borderWidth : 2)
      (UIColor(mapModelHex: m.color) ?? .systemBlue).setFill()
      context.cgContext.fillEllipse(in: rect.insetBy(dx: ring, dy: ring))
    }
  }

  private static func drawAspectFill(_ image: UIImage, in rect: CGRect) {
    let s = max(rect.width / max(1, image.size.width), rect.height / max(1, image.size.height))
    let size = CGSize(width: image.size.width * s, height: image.size.height * s)
    image.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                          width: size.width, height: size.height))
  }

  private static func drawBadges(_ badges: [MunimMarkerBadge], around rect: CGRect, in cg: CGContext) {
    for badge in badges where !badge.text.isEmpty {
      let font = UIFont.systemFont(ofSize: 10, weight: .heavy)
      let color = UIColor(mapModelHex: badge.textColor) ?? .white
      let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
      let text = badge.text as NSString
      let textSize = text.size(withAttributes: attributes)
      let h: CGFloat = 18
      let w = max(h, ceil(textSize.width) + 9)
      let center: CGPoint
      switch badge.position {
      case .topLeft: center = CGPoint(x: rect.minX + w / 2 - 6, y: rect.minY + h / 2 - 6)
      case .topRight: center = CGPoint(x: rect.maxX - w / 2 + 6, y: rect.minY + h / 2 - 6)
      case .bottomLeft: center = CGPoint(x: rect.minX + w / 2 - 6, y: rect.maxY - h / 2 + 6)
      case .bottomRight: center = CGPoint(x: rect.maxX - w / 2 + 6, y: rect.maxY - h / 2 + 6)
      case .bottom: center = CGPoint(x: rect.midX, y: rect.maxY - h / 2 + 6)
      }
      let pill = CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
      let path = UIBezierPath(roundedRect: pill, cornerRadius: h / 2)
      (UIColor(mapModelHex: badge.color) ?? UIColor(white: 0.07, alpha: 1)).setFill()
      path.fill()
      UIColor.white.setStroke()
      path.lineWidth = 1.5
      path.stroke()
      text.draw(at: CGPoint(x: pill.midX - textSize.width / 2, y: pill.midY - textSize.height / 2),
                withAttributes: attributes)
    }
  }
}
