//
//  ButtonsDynamicEffectView.swift
//  DeltaCore
//
//  Renders per-item button/d-pad artwork declared via the item-level "asset" key
//  (ManicEMU-style skins) and animates presses. Ported from ManicEMU's DeltaCore fork
//  (github.com/Daiuno/DeltaCore, branch `manicemu`). Skins without item assets create
//  no subviews, so classic Delta skins are unaffected.
//

import UIKit

#if FRAMEWORK || STATIC_LIBRARY || SWIFT_PACKAGE
import ZIPFoundation
#endif

public class ButtonsDynamicEffectView: UIView
{
    var items: [ControllerSkin.Item]? {
        didSet {
            self.updateItems()
        }
    }

    var archive: Archive?

    weak var appPlacementLayoutGuide: UILayoutGuide?

    public var itemViews = [DynamicEffectView]()

    private var imageCache = [String: (normalImage: UIImage?, selectedImage: UIImage?)]()

    private var previousActivateDate = Date()

    override init(frame: CGRect)
    {
        super.init(frame: frame)
        self.initialize()
    }

    required init?(coder aDecoder: NSCoder)
    {
        super.init(coder: aDecoder)
        self.initialize()
    }

    private func initialize()
    {
        self.backgroundColor = UIColor.clear
        self.isUserInteractionEnabled = false
    }

    public override func layoutSubviews()
    {
        super.layoutSubviews()

        for view in self.itemViews
        {
            var containingFrame = self.bounds
            if let layoutGuide = self.appPlacementLayoutGuide, view.item.placement == .app
            {
                containingFrame = layoutGuide.layoutFrame
            }

            // Item artwork is placed at `frame`, not `extendedFrame` — extended edges are touch-only.
            let frame = view.item.frame.scaled(to: containingFrame)
            view.frame = frame

            guard let archive = self.archive, let asset = view.item.asset else { continue }

            let targetSize = frame.size

            var normalImage: UIImage? = nil
            var selectedImage: UIImage? = nil

            let cacheKey = view.item.id + "\(targetSize)"
            if let cache = self.imageCache[cacheKey]
            {
                normalImage = cache.normalImage
                selectedImage = cache.selectedImage
            }
            else
            {
                if view.item.kind == .button, case .button(let normal, let selected) = asset
                {
                    if let normal = normal, let normalData = self.extract(from: archive, name: normal)
                    {
                        normalImage = UIImage.image(withPDFData: normalData, targetSize: targetSize)
                    }
                    if let selected = selected, let selectedData = self.extract(from: archive, name: selected)
                    {
                        selectedImage = UIImage.image(withPDFData: selectedData, targetSize: targetSize)
                    }
                }
                else if view.item.kind == .dPad, case .dpad(let normal) = asset
                {
                    if let normal = normal, let normalData = self.extract(from: archive, name: normal)
                    {
                        normalImage = UIImage.image(withPDFData: normalData, targetSize: targetSize)
                    }
                }

                if normalImage != nil || selectedImage != nil
                {
                    self.imageCache[cacheKey] = (normalImage, selectedImage)
                }
            }

            view.normalImageView?.image = normalImage
            view.selectedImageView?.image = selectedImage
            if normalImage == nil && selectedImage != nil
            {
                view.selectedImageView?.alpha = 1
            }
        }
    }

    private func extract(from archive: Archive, name: String) -> Data?
    {
        guard let entry = archive[name], let data = try? archive.extract(entry) else { return nil }
        return data
    }

    private func updateItems()
    {
        self.itemViews.forEach { $0.removeFromSuperview() }
        self.imageCache.removeAll()

        var itemViews = [DynamicEffectView]()

        for item in (self.items ?? [])
        {
            switch (item.kind, item.asset)
            {
            case (.button, .button(let normal, let selected)?) where normal != nil || selected != nil: break
            case (.dPad, .dpad(let normal)?) where normal != nil: break
            default: continue
            }

            let itemView = DynamicEffectView(item: item)
            self.addSubview(itemView)
            itemViews.append(itemView)
        }

        self.itemViews = itemViews

        self.setNeedsLayout()
    }

    func activateButtonEffect(input: AnyInput)
    {
        self.previousActivateDate = Date()
        self.findItemView(with: input)?.pressEffect(input)
    }

    func deactivateButtonEffect(input: AnyInput)
    {
        // Very quick taps release before the press animation is perceptible — delay the release a bit.
        let elapsed = Date().timeIntervalSince(self.previousActivateDate)
        if elapsed < 0.06
        {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.findItemView(with: input)?.releaseEffect(input)
            }
        }
        else
        {
            self.findItemView(with: input)?.releaseEffect(input)
        }
    }

    private func findItemView(with input: AnyInput) -> DynamicEffectView?
    {
        for itemView in self.itemViews
        {
            switch itemView.item.inputs
            {
            case .standard(let inputs) where inputs.contains(where: { $0.stringValue == input.stringValue }):
                return itemView

            case .directional(let up, let down, let left, let right)
                where [up, down, left, right].contains(where: { $0.stringValue == input.stringValue }):
                return itemView

            default: continue
            }
        }

        return nil
    }
}

public class DynamicEffectView: UIView
{
    public let item: ControllerSkin.Item

    lazy var normalImageView: UIImageView? = {
        let imageView = UIImageView()
        imageView.alpha = 1
        imageView.contentMode = .center
        imageView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            imageView.topAnchor.constraint(equalTo: self.topAnchor),
            imageView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])
        return imageView
    }()

    lazy var selectedImageView: UIImageView? = {
        guard self.item.kind == .button, case .button(_, let selected)? = self.item.asset, selected != nil else { return nil }

        let imageView = UIImageView()
        imageView.alpha = 0
        imageView.contentMode = .center
        imageView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            imageView.topAnchor.constraint(equalTo: self.topAnchor),
            imageView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])
        return imageView
    }()

    init(item: ControllerSkin.Item)
    {
        self.item = item
        super.init(frame: CGRect.zero)

        self.isAccessibilityElement = true
        switch item.kind
        {
        case .button: self.accessibilityLabel = "button" + item.inputs.allInputs.reduce("", { $0 + " " + $1.stringValue })
        case .dPad: self.accessibilityLabel = "dPad" + item.inputs.allInputs.reduce("", { $0 + " " + $1.stringValue })
        default: break
        }
        self.accessibilityTraits = .button
    }

    required init?(coder aDecoder: NSCoder)
    {
        fatalError("init(coder:) has not been implemented")
    }

    func pressEffect(_ input: AnyInput)
    {
        if self.item.kind == .button
        {
            self.performButtonTransformation(CGAffineTransform(scaleX: 0.9, y: 0.9), isSelected: false)
        }
        else if self.item.kind == .dPad
        {
            var transform = CATransform3DIdentity
            transform.m34 = -1.0 / 500.0 // Perspective, so the d-pad appears to tilt in 3D.

            switch StandardGameControllerInput(rawValue: input.stringValue)
            {
            case .up?:
                transform = CATransform3DScale(CATransform3DTranslate(CATransform3DRotate(transform, .pi / 10, 1, 0, 0), 0, -1.75, 0), 0.95, 1, 1)
            case .down?:
                transform = CATransform3DScale(CATransform3DTranslate(CATransform3DRotate(transform, -.pi / 10, 1, 0, 0), 0, 1.75, 0), 0.95, 1, 1)
            case .left?:
                transform = CATransform3DScale(CATransform3DTranslate(CATransform3DRotate(transform, -.pi / 10, 0, 1, 0), -1.75, 0, 0), 1, 0.95, 1)
            case .right?:
                transform = CATransform3DScale(CATransform3DTranslate(CATransform3DRotate(transform, .pi / 10, 0, 1, 0), 1.75, 0, 0), 1, 0.95, 1)
            default: break
            }

            self.performDPadTransformation(transform)
        }
    }

    func releaseEffect(_ input: AnyInput)
    {
        if self.item.kind == .button
        {
            self.performButtonTransformation(.identity, isSelected: true)
        }
        else if self.item.kind == .dPad
        {
            self.performDPadTransformation(CATransform3DIdentity)
        }
    }

    private func performButtonTransformation(_ transformation: CGAffineTransform, isSelected: Bool)
    {
        let timingParameters = UISpringTimingParameters(dampingRatio: 1.0, initialVelocity: CGVector(dx: 0.2, dy: 0.2))
        let animator = UIViewPropertyAnimator(duration: 0.65, timingParameters: timingParameters)
        animator.addAnimations { [weak self] in
            guard let self = self else { return }

            self.normalImageView?.transform = transformation
            if let selectedImageView = self.selectedImageView
            {
                self.normalImageView?.alpha = isSelected ? 1 : 0
                selectedImageView.transform = transformation
                selectedImageView.alpha = isSelected ? 0 : 1
            }
        }
        animator.isInterruptible = true
        animator.startAnimation()
    }

    private func performDPadTransformation(_ transformation: CATransform3D)
    {
        let timingParameters = UISpringTimingParameters(dampingRatio: 1.0, initialVelocity: CGVector(dx: 0.2, dy: 0.2))
        let animator = UIViewPropertyAnimator(duration: 0.65, timingParameters: timingParameters)
        animator.addAnimations { [weak self] in
            guard let self = self else { return }

            self.normalImageView?.transform3D = transformation
        }
        animator.isInterruptible = true
        animator.startAnimation()
    }
}
