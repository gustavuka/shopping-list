#!/usr/bin/env swift
// Renders the 1024×1024 app icon: the accent-green gradient with a white cart and a check badge.
// Usage: swift scripts/make-app-icon.swift ShoppingList/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
let size = 1024.0
let rect = CGRect(x: 0, y: 0, width: size, height: size)

func drawIcon(in rect: CGRect) {
    // Background: diagonal green gradient (iOS applies the rounded mask itself).
    let gradient = NSGradient(
        starting: NSColor(srgbRed: 0.33, green: 0.85, blue: 0.52, alpha: 1),
        ending: NSColor(srgbRed: 0.10, green: 0.62, blue: 0.36, alpha: 1)
    )!
    gradient.draw(in: rect, angle: -60)

    // Soft highlight in the top-left for depth.
    let glow = NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.22),
        NSColor.white.withAlphaComponent(0.08),
        NSColor.white.withAlphaComponent(0),
    ])!
    glow.draw(fromCenter: CGPoint(x: 220, y: 860), radius: 0, toCenter: CGPoint(x: 220, y: 860), radius: 760, options: [])

    func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight = .semibold, color: NSColor) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            .applying(.init(paletteColors: [color]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    }

    let cart = symbol("cart.fill", pointSize: 470, color: .white)
    let cartSize = cart.size
    cart.draw(in: CGRect(
        x: (size - cartSize.width) / 2 - 20,
        y: (size - cartSize.height) / 2 - 30,
        width: cartSize.width,
        height: cartSize.height
    ))

    // Check badge, top-right of the cart: "shared list, items done".
    let badgeRect = CGRect(x: 610, y: 600, width: 250, height: 250)
    NSColor.white.setFill()
    NSBezierPath(ovalIn: badgeRect).fill()
    let check = symbol("checkmark", pointSize: 140, weight: .black, color: NSColor(srgbRed: 0.12, green: 0.62, blue: 0.36, alpha: 1))
    let checkSize = check.size
    check.draw(in: CGRect(
        x: badgeRect.midX - checkSize.width / 2,
        y: badgeRect.midY - checkSize.height / 2,
        width: checkSize.width,
        height: checkSize.height
    ))
}

// Opaque sRGB context (App Store icons must not have alpha).
let context = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
drawIcon(in: rect)
NSGraphicsContext.restoreGraphicsState()

let png = NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
