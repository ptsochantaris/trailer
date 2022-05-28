import UIKit

final class CountLabel: UILabel {
    
    var badgeColor: UIColor?

	override init(frame: CGRect) {
		super.init(frame: frame)
		isHidden = true
        font = UIFont.preferredFont(forTextStyle: .caption2)
		textAlignment = .center
		translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
	}

	required init(coder aDecoder: NSCoder) {
	    fatalError("init(coder:) has not been implemented")
	}

	override var intrinsicContentSize: CGSize {
		let s = super.intrinsicContentSize
        let side = max(s.height+4, s.width+9)
		return CGSize(width: side, height: side)
	}
    
    override func draw(_ rect: CGRect) {
        guard let b = badgeColor?.cgColor, let c = UIGraphicsGetCurrentContext() else { return }
        c.setFillColor(UIColor.systemBackground.cgColor)
        c.fillEllipse(in: rect)
        c.setFillColor(b)
        c.fillEllipse(in: rect)
        super.draw(rect)
    }

}
