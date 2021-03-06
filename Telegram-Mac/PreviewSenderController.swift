//
//  PreviewSenderController.swift
//  Telegram-Mac
//
//  Created by keepcoder on 02/11/2016.
//  Copyright © 2016 Telegram. All rights reserved.
//

import Cocoa
import TGUIKit
import TelegramCoreMac
import SwiftSignalKitMac
import PostboxMac

private enum SecretMediaTtl {
    case off
    case seconds(Int32)
}

private enum PreviewSenderType {
    case files
    case photo
    case video
    case gif
    case audio
    case media
}

fileprivate enum PreviewSendingState : Int32 {
    case media = 0
    case file = 1
    case collage = 2
}


fileprivate class PreviewSenderView : Control {
    fileprivate let tableView:TableView = TableView()
    fileprivate let textView:TGModernGrowingTextView = TGModernGrowingTextView(frame: NSZeroRect)
    fileprivate let sendButton = ImageButton()
    fileprivate let emojiButton = ImageButton()
    fileprivate let actionsContainerView: View = View()
    fileprivate let headerView: View = View()
    
    fileprivate let closeButton = ImageButton()
    fileprivate let title: TextView = TextView()
    
    fileprivate let photoButton = ImageButton()
    fileprivate let fileButton = ImageButton()
    fileprivate let collageButton = ImageButton()
    
    fileprivate let textContainerView: View = View()
    fileprivate let separator: View = View()
    fileprivate weak var controller: PreviewSenderController? {
        didSet {
            let count = controller?.urls.count ?? 0
            textView.setPlaceholderAttributedString(.initialize(string: count > 1 ? tr(.previewSenderCommentPlaceholder) : tr(.previewSenderCaptionPlaceholder), color: theme.colors.grayText, font: .normal(.text)), update: false)
        }
    }
    let sendAsFile: ValuePromise<PreviewSendingState> = ValuePromise(ignoreRepeated: true)
    private let disposable = MetaDisposable()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        
        separator.backgroundColor = theme.colors.border
        
        closeButton.set(image: theme.icons.modalClose, for: .Normal)
        closeButton.sizeToFit()
        
        
        photoButton.toolTip = tr(.previewSenderMediaTooltip)
        fileButton.toolTip = tr(.previewSenderFileTooltip)
        collageButton.toolTip = tr(.previewSenderCollageTooltip)
        
        photoButton.set(image: ControlStyle(highlightColor: theme.colors.grayIcon).highlight(image: theme.icons.chatAttachPhoto), for: .Normal)
        photoButton.sizeToFit()
        
        disposable.set(sendAsFile.get().start(next: { [weak self] value in
            self?.fileButton.isSelected = value == .file
            self?.photoButton.isSelected = value == .media
            self?.collageButton.isSelected = value == .collage
        }))
        
        photoButton.isSelected = true
        
        photoButton.set(handler: { [weak self] _ in
            self?.sendAsFile.set(.media)
            FastSettings.toggleIsNeedCollage(false)
        }, for: .Click)
        
        collageButton.set(handler: { [weak self] _ in
            self?.sendAsFile.set(.collage)
            FastSettings.toggleIsNeedCollage(true)
        }, for: .Click)
        
        fileButton.set(handler: { [weak self] _ in
            self?.sendAsFile.set(.file)
        }, for: .Click)
        
        closeButton.set(handler: { [weak self] _ in
            self?.controller?.close()
        }, for: .Click)
        
        fileButton.set(image: ControlStyle(highlightColor: theme.colors.grayIcon).highlight(image: theme.icons.chatAttachFile), for: .Normal)
        fileButton.sizeToFit()
        
        collageButton.set(image: theme.icons.previewCollage, for: .Normal)
        collageButton.sizeToFit()
        
        title.backgroundColor = theme.colors.background
        
        headerView.addSubview(closeButton)
        headerView.addSubview(title)
        headerView.addSubview(fileButton)
        headerView.addSubview(photoButton)
        headerView.addSubview(collageButton)
        
        title.isSelectable = false
        title.userInteractionEnabled = false
        
        sendButton.set(image: theme.icons.chatSendMessage, for: .Normal)
        sendButton.sizeToFit()
        
        emojiButton.set(image: theme.icons.chatEntertainment, for: .Normal)
        emojiButton.sizeToFit()
        
        actionsContainerView.addSubview(sendButton)
        actionsContainerView.addSubview(emojiButton)
        
        
        actionsContainerView.setFrameSize(sendButton.frame.width + emojiButton.frame.width + 40, 50)
        
        emojiButton.centerY(x: 0)
        sendButton.centerY(x: emojiButton.frame.maxX + 20)
        
        backgroundColor = theme.colors.background
        textView.background = theme.colors.background
        textView.textFont = .normal(.text)
        textView.textColor = theme.colors.text
        textView.linkColor = theme.colors.link
        textView.max_height = 120
        
        emojiButton.set(handler: { [weak self] control in
            self?.controller?.showEmoji(for: control)
        }, for: .Hover)
        
        sendButton.set(handler: { [weak self] _ in
            self?.controller?.send()
        }, for: .SingleClick)
        
        textView.setFrameSize(NSMakeSize(0, 34))

        addSubview(tableView)

        
        textContainerView.addSubview(textView)
        
        addSubview(headerView)
        addSubview(textContainerView)
        addSubview(actionsContainerView)
        
        addSubview(separator)

    }
    
    deinit {
        disposable.dispose()
    }
    
    var additionHeight: CGFloat {
        return max(50, textView.frame.height + 16) + headerView.frame.height - 12
    }
    
    func updateTitle(_ medias: [Media], state: PreviewSendingState) -> Void {
        
        
        let count = medias.count
        let type: PreviewSenderType
        
        var isPhotos = false
        var isMedia = false
        
       
        if medias.filter({$0 is TelegramMediaImage}).count == medias.count {
            type = .photo
            isPhotos = true
        } else {
            let files = medias.filter({$0 is TelegramMediaFile}).map({$0 as! TelegramMediaFile})
            
            let imagesCount = medias.filter({$0 is TelegramMediaImage}).count
            let count = files.filter({ file in
                
                if file.isVideo && !file.isAnimated {
                    return true
                }
                if let ext = file.fileName?.nsstring.pathExtension.lowercased() {
                    return photoExts.contains(ext) || videoExts.contains(ext)
                }
                return false
            }).count
            
            isMedia = count == (files.count + imagesCount) || count == files.count
            
            if files.filter({$0.isMusic}).count == files.count {
                type = imagesCount > 0 ? .media : .audio
            } else if files.filter({$0.isVideo && !$0.isAnimated}).count == files.count {
                type = imagesCount > 0 ? .media : .video
            } else if files.filter({$0.isVideo && $0.isAnimated}).count == files.count {
                type = imagesCount > 0 ? .media : .gif
            } else if files.filter({!$0.isVideo || !$0.isAnimated || $0.isMusic}).count != medias.count {
                type = .media
            } else {
                type = .files
            }
        }
        
        self.collageButton.isHidden = (!isPhotos && !isMedia) || medias.count > 10 || medias.count < 2
        
        let text:String
        switch type {
        case .files:
            text = tr(.previewSenderSendFileCountable(count))
        case .photo:
            text = tr(.previewSenderSendPhotoCountable(count))
        case .video:
            text = tr(.previewSenderSendVideoCountable(count))
        case .gif:
            text = tr(.previewSenderSendGifCountable(count))
        case .audio:
            text = tr(.previewSenderSendAudioCountable(count))
        case .media:
            text = tr(.previewSenderSendMediaCountable(count))
        }
        
        let layout = TextViewLayout(.initialize(string: text, color: theme.colors.text, font: .medium(.title)), maximumNumberOfLines: 1)
        title.update(layout)
        needsLayout = true
        separator.isHidden = tableView.listHeight <= frame.height - additionHeight
    }
    
    func updateHeight(_ height: CGFloat, _ animated: Bool) {
        CATransaction.begin()
        textContainerView.change(size: NSMakeSize(frame.width, height + 16), animated: animated)
        textContainerView.change(pos: NSMakePoint(0, frame.height - textContainerView.frame.height), animated: animated)
        textView._change(pos: NSMakePoint(10, height == 34 ? 8 : 11), animated: animated)

        actionsContainerView.change(pos: NSMakePoint(frame.width - actionsContainerView.frame.width, frame.height - actionsContainerView.frame.height), animated: animated)

        separator.change(pos: NSMakePoint(0, textContainerView.frame.minY), animated: animated)
        separator.change(opacity: tableView.listHeight > frame.height - additionHeight ? 1.0 : 0.0, animated: animated)
        CATransaction.commit()
        
        needsLayout = true
    }
    
    func applyOptions(_ options:[PreviewOptions]) {
        fileButton.isHidden = !options.contains(.media)
        photoButton.isHidden = !options.contains(.media)
    }
    
    override func layout() {
        super.layout()
        actionsContainerView.setFrameOrigin(frame.width - actionsContainerView.frame.width, frame.height - actionsContainerView.frame.height)
        headerView.setFrameSize(frame.width, 50)
        
        
        tableView.setFrameSize(NSMakeSize(frame.width, frame.height - additionHeight))
        tableView.centerX(y: headerView.frame.maxY - 6)
        
        title.layout?.measure(width: frame.width - 100)
        title.update(title.layout)
        title.centerX()
        title.centerY()
        
        closeButton.centerY(x: headerView.frame.width - closeButton.frame.width - 10)
        collageButton.centerY(x: closeButton.frame.minX - 10 - collageButton.frame.width)

        
        photoButton.centerY(x: 10)
        fileButton.centerY(x: photoButton.frame.maxX + 10)
        
        
        textContainerView.setFrameSize(frame.width, textView.frame.height + 16)
        textContainerView.setFrameOrigin(0, frame.height - textContainerView.frame.height)
        textView.setFrameSize(NSMakeSize(textContainerView.frame.width - 10 - actionsContainerView.frame.width, textView.frame.height))
        textView.setFrameOrigin(10, textView.frame.height == 34 ? 8 : 11)
        
        separator.frame = NSMakeRect(0, textContainerView.frame.minY, frame.width, .borderSize)

    }
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class PreviewSenderController: ModalViewController, TGModernGrowingDelegate {

    fileprivate let urls:[URL]
    private let account:Account
    private let chatInteraction:ChatInteraction
    private var sendingState:PreviewSendingState = .file
    private let disposable = MetaDisposable()
    private let emoji: EmojiViewController
    private var cachedMedia:[PreviewSendingState: (media: [Media], items: [TableRowItem])] = [:]
    
    private let isFileDisposable = MetaDisposable()
    
    override func viewClass() -> AnyClass {
        return PreviewSenderView.self
    }
    
    private var genericView:PreviewSenderView {
        return self.view as! PreviewSenderView
    }
    
    
    func makeItems(_ urls:[URL])  {
        
        if urls.isEmpty {
            return
        }
        
        let initialSize = atomicSize
        let account = self.account
        
        let options = takeSenderOptions(for: urls)
        genericView.applyOptions(options)
        
        let reorder: (Int, Int) -> Void = { [weak self] from, to in
            guard let `self` = self else {return}
            let medias:[PreviewSendingState] = [.media, .file, .collage]
            for type in medias {
                self.cachedMedia[type]?.media.move(at: from, to: to)
                if type != .collage {
                    self.cachedMedia[type]?.items.move(at: from, to: to)
                }
            }
            self.updateSize(self.frame.width, animated: true)
        }
        
        let signal = genericView.sendAsFile.get() |> mapToSignal { [weak self] state -> Signal<([Media], [TableRowItem], PreviewSendingState), Void> in
            if let cached = self?.cachedMedia[state] {
                return .single((cached.media, cached.items, state))
            } else if state == .collage {
                
                
                
                return combineLatest(urls.map({Sender.generateMedia(for: MediaSenderContainer(path: $0.path, caption: "", isFile: state == .file), account: account)}))
                    |> map { $0.map({$0.0})}
                    |> map { media in
                        var id:Int32 = 0
                        let groups = media.map({ media -> Message in
                            id += 1
                            return Message(media, stableId: UInt32(id), messageId: MessageId(peerId: PeerId(0), namespace: 0, id: id))
                        }).chunks(10)
                        
                        return (media, groups.map({MediaGroupPreviewRowItem(initialSize.modify{$0}, messages: $0, account: account, reorder: reorder)}), state)
                        
                    }
            } else {
                return combineLatest(urls.map({Sender.generateMedia(for: MediaSenderContainer(path: $0.path, caption: "", isFile: state == .file), account: account)}))
                    |> map { $0.map({$0.0})}
                    |> map { ($0, $0.map{MediaPreviewRowItem(initialSize.modify{$0}, media: $0, account: account)}, state) }
            }
        } |> deliverOnMainQueue
        
        let animated: Atomic<Bool> = Atomic(value: false)
        
        disposable.set(signal.start(next: { [weak self] medias, items, state in
            if let strongSelf = self {
                strongSelf.sendingState = state
                strongSelf.cachedMedia[state] = (media: medias, items: items)
                strongSelf.genericView.updateTitle(medias, state: state)
                strongSelf.genericView.tableView.beginTableUpdates()
                strongSelf.genericView.tableView.removeAll(animation: .effectFade)
                strongSelf.genericView.tableView.insert(items: items, animation: .effectFade)
                strongSelf.genericView.tableView.endTableUpdates()
                strongSelf.genericView.layout()
                
                let animated = animated.swap(true)
                
                let maxWidth = animated ? strongSelf.frame.width : max(items.map({$0.layoutSize.width}).max()! + 20, 350)
                strongSelf.updateSize(maxWidth, animated: animated)
                strongSelf.readyOnce()
            }
        }))
    }
    
    private func updateSize(_ width: CGFloat, animated: Bool) {
        if let contentSize = self.window?.contentView?.frame.size {
            self.modal?.resize(with:NSMakeSize(width, min(contentSize.height - 70, genericView.tableView.listHeight + max(genericView.additionHeight, 88))), animated: animated)
        }
    }
  
    override var dynamicSize: Bool {
        return true
    }
    
    override func returnKeyAction() -> KeyHandlerResult {
        if let currentEvent = NSApp.currentEvent {
            if FastSettings.checkSendingAbility(for: currentEvent) {
                send()
                return .invoked
            }
        }
        
        return .invokeNext
    }
    
    func send() {
        emoji.popover?.hide()
        self.modal?.close(true)
        var caption = genericView.textView.string()
        if let cached = cachedMedia[sendingState] {
            if cached.media.count > 1 && !caption.isEmpty {
                chatInteraction.forceSendMessage(caption)
                caption = ""
            }
            chatInteraction.sendMedias(cached.media, caption, sendingState == .collage)
        }
    }
    
    
    override func measure(size: NSSize) {
        self.modal?.resize(with:NSMakeSize(genericView.frame.width, min(size.height - 70, genericView.tableView.listHeight + max(genericView.additionHeight, 88))), animated: false)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        genericView.controller = self
        genericView.textView.delegate = self
        genericView.sendAsFile.set(sendingState)
        let interactions = EntertainmentInteractions(.emoji, peerId: chatInteraction.peerId)
        
        interactions.sendEmoji = { [weak self] emoji in
            self?.genericView.textView.appendText(emoji)
        }
        
        emoji.update(with: interactions)
        
        makeItems(self.urls)
    }
    
    deinit {
        disposable.dispose()
        isFileDisposable.dispose()
    }
    
    override func becomeFirstResponder() -> Bool? {
        return true
    }
    override func firstResponder() -> NSResponder? {
        return genericView.textView
    }
    
    init(urls:[URL], account:Account, chatInteraction:ChatInteraction, asMedia:Bool = true) {
        self.urls = urls
        self.account = account
        self.emoji = EmojiViewController(account)
        
        var canCollage: Bool = urls.count > 1
        for url in urls {
            if !photoExts.contains(url.pathExtension.lowercased()) && !videoExts.contains(url.pathExtension.lowercased()) {
                canCollage = false
                break
            }
        }
        
        self.sendingState = asMedia ? FastSettings.isNeedCollage && canCollage ? .collage : .media : .file
        self.chatInteraction = chatInteraction
        super.init(frame:NSMakeRect(0,0,300, 300))
        bar = .init(height: 0)
    }
    
    func showEmoji(for control: Control) {
        showPopover(for: control, with: emoji)
    }
    
    func textViewHeightChanged(_ height: CGFloat, animated: Bool) {
        
        updateSize(frame.width, animated: animated)
        
        genericView.updateHeight(height, animated)
        
    }
    
    func textViewEnterPressed(_ event: NSEvent) -> Bool {
        if FastSettings.checkSendingAbility(for: event) {
            return true
        }
        return false
    }
    
    func textViewTextDidChange(_ string: String) {
        
    }
    
    func textViewTextDidChangeSelectedRange(_ range: NSRange) {
        
    }
    
    func textViewDidReachedLimit(_ textView: Any) {
        genericView.textView.shake()
    }
    
    func textViewDidPaste(_ pasteboard: NSPasteboard) -> Bool {
        return false
    }
    
    func textViewSize() -> NSSize {
        return NSMakeSize(frame.width - 40, genericView.textView.frame.height)
    }
    
    func textViewIsTypingEnabled() -> Bool {
        return true
    }
    
    func maxCharactersLimit() -> Int32 {
        return 200
    }
    
}
