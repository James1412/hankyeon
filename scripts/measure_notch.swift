import AppKit
for screen in NSScreen.screens {
    let height = screen.safeAreaInsets.top
    if height > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
        print("\(screen.localizedName): display \(screen.frame.width)×\(screen.frame.height) pt, notch \(right.minX - left.maxX)×\(height) pt, backing scale \(screen.backingScaleFactor)")
    } else {
        print("\(screen.localizedName): no notch reported")
    }
}
