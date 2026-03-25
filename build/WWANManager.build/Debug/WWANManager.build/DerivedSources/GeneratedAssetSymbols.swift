import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(DeveloperToolsSupport)
import DeveloperToolsSupport
#endif

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
#else
private class ResourceBundleClass {}
private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
#endif

// MARK: - Color Symbols -

@available(iOS 11.0, macOS 10.13, tvOS 11.0, *)
extension ColorResource {

}

// MARK: - Image Symbols -

@available(iOS 11.0, macOS 10.7, tvOS 11.0, *)
extension ImageResource {

    /// The "Celluar" asset catalog image resource.
    static let celluar = ImageResource(name: "Celluar", bundle: resourceBundle)

    /// The "Connecting0" asset catalog image resource.
    static let connecting0 = ImageResource(name: "Connecting0", bundle: resourceBundle)

    #warning("The \"Connecting0_\" image asset name resolves to the symbol \"connecting0\" which already exists. Try renaming the asset.")

    /// The "Connecting1" asset catalog image resource.
    static let connecting1 = ImageResource(name: "Connecting1", bundle: resourceBundle)

    #warning("The \"Connecting1_\" image asset name resolves to the symbol \"connecting1\" which already exists. Try renaming the asset.")

    /// The "Connecting2" asset catalog image resource.
    static let connecting2 = ImageResource(name: "Connecting2", bundle: resourceBundle)

    #warning("The \"Connecting2_\" image asset name resolves to the symbol \"connecting2\" which already exists. Try renaming the asset.")

    /// The "Connecting3" asset catalog image resource.
    static let connecting3 = ImageResource(name: "Connecting3", bundle: resourceBundle)

    #warning("The \"Connecting3_\" image asset name resolves to the symbol \"connecting3\" which already exists. Try renaming the asset.")

    /// The "Offline" asset catalog image resource.
    static let offline = ImageResource(name: "Offline", bundle: resourceBundle)

    #warning("The \"Offline_\" image asset name resolves to the symbol \"offline\" which already exists. Try renaming the asset.")

    /// The "Signal0" asset catalog image resource.
    static let signal0 = ImageResource(name: "Signal0", bundle: resourceBundle)

    #warning("The \"Signal0_\" image asset name resolves to the symbol \"signal0\" which already exists. Try renaming the asset.")

    /// The "Signal1" asset catalog image resource.
    static let signal1 = ImageResource(name: "Signal1", bundle: resourceBundle)

    #warning("The \"Signal1_\" image asset name resolves to the symbol \"signal1\" which already exists. Try renaming the asset.")

    /// The "Signal2" asset catalog image resource.
    static let signal2 = ImageResource(name: "Signal2", bundle: resourceBundle)

    #warning("The \"Signal2_\" image asset name resolves to the symbol \"signal2\" which already exists. Try renaming the asset.")

    /// The "Signal3" asset catalog image resource.
    static let signal3 = ImageResource(name: "Signal3", bundle: resourceBundle)

    #warning("The \"Signal3_\" image asset name resolves to the symbol \"signal3\" which already exists. Try renaming the asset.")

    /// The "Signal4" asset catalog image resource.
    static let signal4 = ImageResource(name: "Signal4", bundle: resourceBundle)

    #warning("The \"Signal4_\" image asset name resolves to the symbol \"signal4\" which already exists. Try renaming the asset.")

    /// The "app" asset catalog image resource.
    static let app = ImageResource(name: "app", bundle: resourceBundle)

}

// MARK: - Color Symbol Extensions -

#if canImport(AppKit)
@available(macOS 10.13, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

}
#endif

#if canImport(UIKit)
@available(iOS 11.0, tvOS 11.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

}
#endif

#if canImport(SwiftUI)
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension SwiftUI.Color {

}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

}
#endif

// MARK: - Image Symbol Extensions -

#if canImport(AppKit)
@available(macOS 10.7, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

    /// The "Celluar" asset catalog image.
    static var celluar: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .celluar)
#else
        .init()
#endif
    }

    /// The "Connecting0" asset catalog image.
    static var connecting0: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .connecting0)
#else
        .init()
#endif
    }

    /// The "Connecting1" asset catalog image.
    static var connecting1: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .connecting1)
#else
        .init()
#endif
    }

    /// The "Connecting2" asset catalog image.
    static var connecting2: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .connecting2)
#else
        .init()
#endif
    }

    /// The "Connecting3" asset catalog image.
    static var connecting3: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .connecting3)
#else
        .init()
#endif
    }

    /// The "Offline" asset catalog image.
    static var offline: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .offline)
#else
        .init()
#endif
    }

    /// The "Signal0" asset catalog image.
    static var signal0: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .signal0)
#else
        .init()
#endif
    }

    /// The "Signal1" asset catalog image.
    static var signal1: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .signal1)
#else
        .init()
#endif
    }

    /// The "Signal2" asset catalog image.
    static var signal2: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .signal2)
#else
        .init()
#endif
    }

    /// The "Signal3" asset catalog image.
    static var signal3: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .signal3)
#else
        .init()
#endif
    }

    /// The "Signal4" asset catalog image.
    static var signal4: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .signal4)
#else
        .init()
#endif
    }

    /// The "app" asset catalog image.
    static var app: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .app)
#else
        .init()
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 11.0, tvOS 11.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    /// The "Celluar" asset catalog image.
    static var celluar: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .celluar)
#else
        .init()
#endif
    }

    /// The "Connecting0" asset catalog image.
    static var connecting0: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .connecting0)
#else
        .init()
#endif
    }

    /// The "Connecting1" asset catalog image.
    static var connecting1: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .connecting1)
#else
        .init()
#endif
    }

    /// The "Connecting2" asset catalog image.
    static var connecting2: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .connecting2)
#else
        .init()
#endif
    }

    /// The "Connecting3" asset catalog image.
    static var connecting3: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .connecting3)
#else
        .init()
#endif
    }

    /// The "Offline" asset catalog image.
    static var offline: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .offline)
#else
        .init()
#endif
    }

    /// The "Signal0" asset catalog image.
    static var signal0: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .signal0)
#else
        .init()
#endif
    }

    /// The "Signal1" asset catalog image.
    static var signal1: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .signal1)
#else
        .init()
#endif
    }

    /// The "Signal2" asset catalog image.
    static var signal2: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .signal2)
#else
        .init()
#endif
    }

    /// The "Signal3" asset catalog image.
    static var signal3: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .signal3)
#else
        .init()
#endif
    }

    /// The "Signal4" asset catalog image.
    static var signal4: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .signal4)
#else
        .init()
#endif
    }

    /// The "app" asset catalog image.
    static var app: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .app)
#else
        .init()
#endif
    }

}
#endif

// MARK: - Thinnable Asset Support -

@available(iOS 11.0, macOS 10.13, tvOS 11.0, *)
@available(watchOS, unavailable)
extension ColorResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if AppKit.NSColor(named: NSColor.Name(thinnableName), bundle: bundle) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIColor(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(UIKit)
@available(iOS 11.0, tvOS 11.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    private convenience init?(thinnableResource: ColorResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension SwiftUI.Color {

    private init?(thinnableResource: ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

    private init?(thinnableResource: ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}
#endif

@available(iOS 11.0, macOS 10.7, tvOS 11.0, *)
@available(watchOS, unavailable)
extension ImageResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if bundle.image(forResource: NSImage.Name(thinnableName)) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIImage(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(AppKit)
@available(macOS 10.7, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

    private convenience init?(thinnableResource: ImageResource?) {
#if !targetEnvironment(macCatalyst)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 11.0, tvOS 11.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    private convenience init?(thinnableResource: ImageResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

// MARK: - Backwards Deployment Support -

/// A color resource.
struct ColorResource: Swift.Hashable, Swift.Sendable {

    /// An asset catalog color resource name.
    fileprivate let name: Swift.String

    /// An asset catalog color resource bundle.
    fileprivate let bundle: Foundation.Bundle

    /// Initialize a `ColorResource` with `name` and `bundle`.
    init(name: Swift.String, bundle: Foundation.Bundle) {
        self.name = name
        self.bundle = bundle
    }

}

/// An image resource.
struct ImageResource: Swift.Hashable, Swift.Sendable {

    /// An asset catalog image resource name.
    fileprivate let name: Swift.String

    /// An asset catalog image resource bundle.
    fileprivate let bundle: Foundation.Bundle

    /// Initialize an `ImageResource` with `name` and `bundle`.
    init(name: Swift.String, bundle: Foundation.Bundle) {
        self.name = name
        self.bundle = bundle
    }

}

#if canImport(AppKit)
@available(macOS 10.13, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

    /// Initialize a `NSColor` with a color resource.
    convenience init(resource: ColorResource) {
        self.init(named: NSColor.Name(resource.name), bundle: resource.bundle)!
    }

}

protocol _ACResourceInitProtocol {}
extension AppKit.NSImage: _ACResourceInitProtocol {}

@available(macOS 10.7, *)
@available(macCatalyst, unavailable)
extension _ACResourceInitProtocol {

    /// Initialize a `NSImage` with an image resource.
    init(resource: ImageResource) {
        self = resource.bundle.image(forResource: NSImage.Name(resource.name))! as! Self
    }

}
#endif

#if canImport(UIKit)
@available(iOS 11.0, tvOS 11.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    /// Initialize a `UIColor` with a color resource.
    convenience init(resource: ColorResource) {
#if !os(watchOS)
        self.init(named: resource.name, in: resource.bundle, compatibleWith: nil)!
#else
        self.init()
#endif
    }

}

@available(iOS 11.0, tvOS 11.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    /// Initialize a `UIImage` with an image resource.
    convenience init(resource: ImageResource) {
#if !os(watchOS)
        self.init(named: resource.name, in: resource.bundle, compatibleWith: nil)!
#else
        self.init()
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension SwiftUI.Color {

    /// Initialize a `Color` with a color resource.
    init(_ resource: ColorResource) {
        self.init(resource.name, bundle: resource.bundle)
    }

}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension SwiftUI.Image {

    /// Initialize an `Image` with an image resource.
    init(_ resource: ImageResource) {
        self.init(resource.name, bundle: resource.bundle)
    }

}
#endif