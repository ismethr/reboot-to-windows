// 生成 1024×1024 的 App 图标：蓝色圆角底板 + 环形“重启”箭头 + 中间四个方块。
// 用法：swift make-icon.swift 输出.png

import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "icon-1024.png"

let rep = NSBitmapImageRep(
	bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
	bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
	colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// 底板（macOS 图标网格：824×824，留出阴影空间）
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowBlurRadius = 28
shadow.set()
NSColor.black.setFill()
tilePath.fill()
NSGraphicsContext.restoreGraphicsState()

NSGradient(
	starting: NSColor(srgbRed: 0.20, green: 0.58, blue: 0.95, alpha: 1),
	ending: NSColor(srgbRed: 0.02, green: 0.29, blue: 0.66, alpha: 1)
)!.draw(in: tilePath, angle: -90)

NSColor.white.setFill()
NSColor.white.setStroke()

// 环形箭头：顺时针从右上（60°）绕到左上（120°），顶部留缺口
let center = NSPoint(x: size / 2, y: size / 2 - 6)
let radius: CGFloat = 262
let lineWidth: CGFloat = 46
let arc = NSBezierPath()
arc.appendArc(withCenter: center, radius: radius, startAngle: 58, endAngle: 132, clockwise: true)
arc.lineWidth = lineWidth
arc.lineCapStyle = .round
arc.stroke()

// 箭头头部：位于 132° 处，沿顺时针切线方向指向缺口
let end = 132 * CGFloat.pi / 180
let tip = NSPoint(x: center.x + radius * cos(end), y: center.y + radius * sin(end))
let tangent = NSPoint(x: sin(end), y: -cos(end))   // 顺时针方向
let normal = NSPoint(x: cos(end), y: sin(end))
let head: CGFloat = 70
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: tip.x + tangent.x * head * 1.15, y: tip.y + tangent.y * head * 1.15))
arrow.line(to: NSPoint(x: tip.x + normal.x * head, y: tip.y + normal.y * head))
arrow.line(to: NSPoint(x: tip.x - normal.x * head, y: tip.y - normal.y * head))
arrow.close()
arrow.lineJoinStyle = .round
arrow.lineWidth = 14
arrow.fill()
arrow.stroke()

// 中间 2×2 方块
let cell: CGFloat = 112
let gap: CGFloat = 22
let origin = NSPoint(x: center.x - cell - gap / 2, y: center.y - cell - gap / 2)
for row in 0..<2 {
	for col in 0..<2 {
		let rect = NSRect(
			x: origin.x + CGFloat(col) * (cell + gap),
			y: origin.y + CGFloat(row) * (cell + gap),
			width: cell, height: cell)
		NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).fill()
	}
}

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
