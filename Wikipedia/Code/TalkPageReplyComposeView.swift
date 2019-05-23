
import UIKit

protocol TalkPageReplyComposeViewDelegate: class {
    func composeTextDidChange(text: String?)
     var collectionViewFrame: CGRect { get }
}

class TalkPageReplyComposeView: UIView {
    
    private(set) var composeTextViewFrame: CGRect?
    private(set) var beKindViewFrame: CGRect?
    
    lazy private(set) var composeTextView: ThemeableTextView = ThemeableTextView()
    lazy private(set) var beKindView: InfoBannerView = InfoBannerView()
    lazy private var finePrintTextView: UITextView = UITextView()
    
    weak var delegate: TalkPageReplyComposeViewDelegate?
    
    private var theme: Theme?
    
    private var licenseTitleTextViewAttributedString: NSAttributedString {
        
        //since this is just colors it shouldn't affect sizing
        let colorTheme = theme ?? Theme.light
        
        let localizedString = WMFLocalizedString("talk-page-publish-terms-and-licenses", value: "By saving changes, you agree to the %1$@Terms of Use%2$@, and agree to release your contribution under the %3$@CC BY-SA 3.0%4$@ and the %5$@GFDL%6$@ licenses.", comment: "Text for information about the Terms of Use and edit licenses on talk pages. Parameters:\n* %1$@ - app-specific non-text formatting, %2$@ - app-specific non-text formatting, %3$@ - app-specific non-text formatting, %4$@ - app-specific non-text formatting, %5$@ - app-specific non-text formatting,  %6$@ - app-specific non-text formatting.") //todo: gfd or gfdl?
        
        let substitutedString = String.localizedStringWithFormat(
            localizedString,
            "<a href=\"\(Licenses.saveTermsURL?.absoluteString ?? "")\">",
            "</a>",
            "<a href=\"\(Licenses.CCBYSA3URL?.absoluteString ?? "")\">",
            "</a>" ,
            "<a href=\"\(Licenses.GFDLURL?.absoluteString ?? "")\">",
            "</a>"
        )
        
        let attributedString = substitutedString.byAttributingHTML(with: .caption1, boldWeight: .regular, matching: traitCollection, withBoldedString: nil, color: colorTheme.colors.secondaryText, linkColor: colorTheme.colors.link, tagMapping: nil, additionalTagAttributes: nil)
        
        return attributedString
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func resetCompose() {
        composeTextView.text = nil
        composeTextView.isUserInteractionEnabled = true
    }
    
    func resetComposeTextViewFrame() {
        if let composeTextViewFrame = composeTextViewFrame {
            composeTextView.frame = composeTextViewFrame
        }
    }
    
    func resetBeKindViewFrame() {
        if let beKindViewFrame = beKindViewFrame {
            beKindView.frame = beKindViewFrame
        }
    }
    
    func sizeThatFits(_ size: CGSize, apply: Bool) -> CGSize {
        
        let semanticContentAttribute: UISemanticContentAttribute = traitCollection.layoutDirection == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
        
        let adjustedMargins = UIEdgeInsets(top: layoutMargins.top, left: layoutMargins.left + 7, bottom: layoutMargins.bottom, right: layoutMargins.right + 7)
        
        let composeTextViewOrigin = CGPoint(x: adjustedMargins.left, y: adjustedMargins.top)
        let composeTextViewWidth = size.width - adjustedMargins.left - adjustedMargins.right
        
        let finePrintTextViewOrigin = CGPoint(x: adjustedMargins.left, y: adjustedMargins.top)
        let finePrintTextViewWidth = size.width - adjustedMargins.left - adjustedMargins.right
        
        
        let finePrintFrame = finePrintTextView.wmf_preferredFrame(at: finePrintTextViewOrigin, maximumWidth: finePrintTextViewWidth, minimumWidth: finePrintTextViewWidth, alignedBy: semanticContentAttribute, apply: false) //will apply below
        
        let beKindViewOrigin = CGPoint(x: 0, y: adjustedMargins.top)
        beKindView.layoutMargins = layoutMargins
        let beKindViewSize = beKindView.sizeThatFits(size, apply: apply)
        let beKindViewFrame = CGRect(origin: beKindViewOrigin, size: beKindViewSize)
        
        let forcedComposeHeight = (delegate?.collectionViewFrame.size ?? size).height * 0.67 - (finePrintFrame.height + beKindViewFrame.height)
        
        let composeTextViewFrame = CGRect(x: composeTextViewOrigin.x, y: composeTextViewOrigin.y, width: composeTextViewWidth, height: forcedComposeHeight)
        self.composeTextViewFrame = composeTextViewFrame
        
        if (apply) {
            composeTextView.frame = composeTextViewFrame
            beKindView.frame = CGRect(x: 0, y: composeTextViewFrame.minY + composeTextViewFrame.height, width: size.width, height: beKindViewFrame.height)
            self.beKindViewFrame = beKindView.frame
            finePrintTextView.frame = CGRect(x: adjustedMargins.left, y: composeTextViewFrame.minY + composeTextViewFrame.height + beKindViewFrame.height, width: finePrintTextViewWidth, height: finePrintFrame.height)
        }
        
        let finalHeight = adjustedMargins.top + composeTextViewFrame.size.height + beKindViewFrame.height + finePrintFrame.height + adjustedMargins.bottom
        return CGSize(width: size.width, height: finalHeight)
    }
    
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        return sizeThatFits(size, apply: false)
    }
    
    // MARK - Dynamic Type
    // Only applies new fonts if the content size category changes
    
    open override func setNeedsLayout() {
        maybeUpdateFonts(with: traitCollection)
        super.setNeedsLayout()
    }
    
    override open func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        setNeedsLayout()
    }
    
    var contentSizeCategory: UIContentSizeCategory?
    fileprivate func maybeUpdateFonts(with traitCollection: UITraitCollection) {
        guard contentSizeCategory == nil || contentSizeCategory != traitCollection.wmf_preferredContentSizeCategory else {
            return
        }
        contentSizeCategory = traitCollection.wmf_preferredContentSizeCategory
        updateFonts(with: traitCollection)
    }
    
    func updateFonts(with traitCollection: UITraitCollection) {
        composeTextView.font = UIFont.wmf_font(.body, compatibleWithTraitCollection: traitCollection)
        finePrintTextView.attributedText = licenseTitleTextViewAttributedString
    }
}

//MARK: Private

private extension TalkPageReplyComposeView {
    func setupView() {
        preservesSuperviewLayoutMargins = false
        insetsLayoutMarginsFromSafeArea = false
        autoresizesSubviews = false
        addSubview(composeTextView)
        composeTextView.isUnderlined = false
        composeTextView.isScrollEnabled = true
        composeTextView.placeholderDelegate = self
        composeTextView.placeholder = WMFLocalizedString("talk-page-new-reply-body-placeholder-text", value: "Compose response", comment: "Placeholder text which appears initially in the new reply field for talk pages.")
        insertSubview(finePrintTextView, belowSubview: composeTextView)
        finePrintTextView.isScrollEnabled = false
        finePrintTextView.attributedText = licenseTitleTextViewAttributedString
        insertSubview(beKindView, aboveSubview: composeTextView)
        beKindView.configure(iconName: "heart-icon", title: CommonStrings.talkPageNewBannerTitle, subtitle: CommonStrings.talkPageNewBannerSubtitle)
    }
}

//MARK: Themeable

extension TalkPageReplyComposeView: Themeable {
    func apply(theme: Theme) {
        self.theme = theme
        composeTextView.apply(theme: theme)
        beKindView.apply(theme: theme)
        backgroundColor = theme.colors.paperBackground
        finePrintTextView.backgroundColor = theme.colors.paperBackground
        finePrintTextView.textColor = theme.colors.secondaryText
    }
}

//MARK: ThemeableTextViewPlaceholderDelegate

extension TalkPageReplyComposeView: ThemeableTextViewPlaceholderDelegate {
    func themeableTextViewPlaceholderDidHide(_ themeableTextView: UITextView, isPlaceholderHidden: Bool) {
        //no-op
    }
    
    func themeableTextViewDidChange(_ themeableTextView: UITextView) {
        delegate?.composeTextDidChange(text: themeableTextView.text)
    }
}