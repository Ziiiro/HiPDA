//
//  PostViewController.swift
//  HiPDA
//
//  Created by leizh007 on 2017/5/15.
//  Copyright © 2017年 HiPDA. All rights reserved.
//

import UIKit
import WebKit
import WebViewJavascriptBridge
import MJRefresh
import MLeaksFinder
import Perform
import Argo
import SDWebImage
import Then

/// 浏览帖子页面
class PostViewController: BaseViewController {
    fileprivate static let shared = PostViewController.load(from: .home)
    
    var postInfo: PostInfo! {
        didSet {
            guard let viewModel = viewModel else { return }
            viewModel.postInfo = postInfo
        }
    }
    
    fileprivate var viewModel: PostViewModel!
    fileprivate var webView: BaseWebView!
    fileprivate var bridge: WKWebViewJavascriptBridge!
    fileprivate var postOperationViewController: PostOperationViewController?
    fileprivate var isLoading = false
    fileprivate lazy var moreButton: UIButton = { [unowned self] _ in
        let more = UIButton(type: .system)
        more.tintColor = C.Color.navigationBarTintColor
        more.setImage(#imageLiteral(resourceName: "post_more"), for: .normal)
        more.addTarget(self, action: #selector(self.moreButtonPressed), for: .touchUpInside)
        more.frame = CGRect(x: 0.0, y: 0.0, width: 20.0, height: 24.0)
        return more
        }()
    fileprivate lazy var activityIndicator: UIActivityIndicatorView = { [unowned self] _ in
        let frame = CGRect(x: 0.0, y: 0.0, width: 30.0, height: 22.0)
        let indicator = UIActivityIndicatorView(frame: frame)
        indicator.activityIndicatorViewStyle = .white
        indicator.color = C.Color.navigationBarTintColor
        indicator.startAnimating()
        return indicator
        }()
    fileprivate lazy var refreshButton: UIButton = { [unowned self] _ in
        let frame = CGRect(x: 0.0, y: 0.0, width: 30.0, height: 22.0)
        let button = UIButton(type: .system)
        button.tintColor = C.Color.navigationBarTintColor
        button.setImage(#imageLiteral(resourceName: "post_refresh"), for: .normal)
        button.addTarget(self, action: #selector(self.refreshButtonPressed), for: .touchUpInside)
        button.frame = frame
        button.contentMode = .scaleAspectFit
        return button
        }()
    fileprivate lazy var replyButton: UIButton = { [unowned self] _ in
        let button = UIButton(type: .system)
        button.tintColor = C.Color.navigationBarTintColor
        button.setImage(#imageLiteral(resourceName: "post_reply"), for: .normal)
        button.addTarget(self, action: #selector(self.replyButtonPressed), for: .touchUpInside)
        button.frame = CGRect(x: 0.0, y: 0.0, width: 32.0, height: 24.0)
        return button
        }()
    fileprivate lazy var pageNumberButton: UIButton = { [unowned self] _ in
        let button = UIButton(type: .system)
        button.tintColor = C.Color.navigationBarTintColor
        button.titleLabel?.font = UIFont.boldSystemFont(ofSize: 20.0)
        button.addTarget(self, action: #selector(self.pageNumberButtonPressed), for: .touchUpInside)
        return button
        }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        viewModel = PostViewModel(postInfo: postInfo)
        webView = BaseWebView()
        view.addSubview(webView)
        bridge = WKWebViewJavascriptBridge(for: webView)
        bridge.setWebViewDelegate(self)
        skinWebView(webView)
        skinWebViewJavascriptBridge(bridge)
        loadData()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        let yOffset = C.UI.navigationBarHeight + C.UI.statusBarHeight
        webView.frame = CGRect(x: 0,
                               y: yOffset,
                               width: view.bounds.size.width,
                               height: view.bounds.size.height - yOffset)
    }
    
    override func willMove(toParentViewController parent: UIViewController?) {
        super.willMove(toParentViewController: parent)
        
        postOperationViewController?.dismiss(animation: false)
        postOperationViewController = nil
    }
    
    func canJump(to postInfo: PostInfo) -> Bool {
        return postInfo.authorid == self.viewModel.postInfo.authorid &&
            postInfo.tid == self.viewModel.postInfo.tid &&
            postInfo.page == self.viewModel.postInfo.page &&
            viewModel.contains(pid: postInfo.pid)
    }
    
    func jump(to postInfo: PostInfo) {
        guard canJump(to: postInfo) else { return }
        if let pid =  postInfo.pid {
            bridge.callHandler("jumpToPid", data: pid)
        }
    }
    
    fileprivate func updateWebViewState() {
        let states: [MJRefreshState] = [.idle, .pulling, .refreshing]
        for state in states {
            webView.refreshHeader?.setTitle(viewModel.headerTitle(for: state), for: state)
        }
    }
    
    override func configureApperance(of navigationBar: UINavigationBar) {
        if navigationController?.viewControllers.count == 1 {
            navigationItem.leftBarButtonItem = UIBarButtonItem(image: #imageLiteral(resourceName: "image_browser_close"), style: .plain, target: self, action: #selector(close))
        }
    }
    
    fileprivate func skinRightBarButtonItems() {
        let title = self.viewModel.totalPage == .max ? "\(self.viewModel.postInfo.page)/?" : "\(self.viewModel.postInfo.page)/\(self.viewModel.totalPage)"
        pageNumberButton.setTitle(title, for: .normal)
        pageNumberButton.sizeToFit()
        navigationItem.rightBarButtonItems = [UIBarButtonItem(customView: moreButton),
                                              UIBarButtonItem(customView: isLoading ? activityIndicator : refreshButton),
                                              UIBarButtonItem(customView: replyButton),
                                              UIBarButtonItem(customView: pageNumberButton)]
    }
    
    fileprivate func animationOptions(of status: PostViewStatus) -> UIViewAnimationOptions {
        switch status {
        case .loadingFirstPage:
            return [.allowAnimatedContent]
        case .loadingPreviousPage:
            return [.transitionCurlDown, .allowAnimatedContent]
        case .loadingNextPage:
            return [.transitionCurlUp, .allowAnimatedContent]
        default:
            return [.allowAnimatedContent]
        }
    }
    
    fileprivate func  handleDataLoadResult(_ result: PostResult) {
        switch result {
        case .success(let html):
            if viewModel.hasData {
                let options = animationOptions(of: viewModel.status)
                UIView.transition(with: webView, duration: C.UI.animationDuration * 4.0, options: options, animations: {
                    self.webView.loadHTMLString(html, baseURL: C.URL.baseWebViewURL)
                    self.configureWebViewAfterLoadData()
                }, completion: nil)
            } else {
                webView.endRefreshing()
                webView.endLoadMore()
                webView.status = .noResult
                viewModel.status = .idle
            }
        case .failure(let error):
            showPromptInformation(of: .failure("\(error)"))
            viewModel.status = .idle
            if webView.status == .loading {
                webView.status = .tapToLoad
            } else {
                webView.endRefreshing()
                webView.endLoadMore()
            }
            isLoading = false
            skinRightBarButtonItems()
        }
    }
    
    fileprivate func configureWebViewAfterLoadData() {
        if webView.status == .pullUpLoading {
            if viewModel.hasMoreData {
                webView.endLoadMore()
                webView.resetNoMoreData()
            } else {
                webView.endLoadMoreWithNoMoreData()
            }
        } else if webView.status ==  .pullDownRefreshing {
            webView.endRefreshing()
            if viewModel.hasMoreData {
                webView.resetNoMoreData()
            } else {
                webView.endLoadMoreWithNoMoreData()
            }
        } else {
            if viewModel.hasMoreData {
                webView.resetNoMoreData()
            } else {
                webView.endLoadMoreWithNoMoreData()
            }
        }
        webView.status = .normal
        viewModel.status = .idle
    }
}

// MARK: - Button & Actions

extension PostViewController {
    func close() {
        postOperationViewController?.dismiss()
        postOperationViewController = nil
        presentingViewController?.dismiss(animated: true, completion: nil)
    }
    
    func moreButtonPressed() {
        postOperationViewController?.dismiss()
        postOperationViewController = nil
        if let postOperationViewController = postOperationViewController {
            postOperationViewController.dismiss()
            self.postOperationViewController = nil
        } else {
            let postOperationViewController = PostOperationViewController.load(from: .home)
            self.postOperationViewController = postOperationViewController
            postOperationViewController.display(in: self, frame: view.bounds)
            postOperationViewController.delegate = self
        }
    }
    
    func refreshButtonPressed() {
        postOperationViewController?.dismiss()
        postOperationViewController = nil
        isLoading = true
        skinRightBarButtonItems()
        loadData()
    }
    
    func replyButtonPressed() {
        postOperationViewController?.dismiss()
        postOperationViewController = nil
    }
    
    func pageNumberButtonPressed() {
        postOperationViewController?.dismiss()
        postOperationViewController = nil
        guard viewModel.totalPage != .max else { return }
    }
}

// MARK: - PostOperationDelegate

extension PostViewController: PostOperationDelegate {
    func operationCancelled() {
        postOperationViewController?.dismiss()
        postOperationViewController = nil
    }
    
    func didSelected(_ operation: PostOperation) {
        postOperationViewController?.dismiss()
        postOperationViewController = nil
        switch operation {
        case .collection:
            break
        case .attention:
            break
        case .top:
            bridge.callHandler("scrollToTop")
        case .bottom:
            bridge.callHandler("scrollToBottom")
        }
    }
}

// MARK: - Initialization Configure

extension PostViewController {
    fileprivate func skinWebView(_ webView: BaseWebView) {
        webView.hasRefreshHeader = true
        webView.hasLoadMoreFooter = true
        webView.loadMoreFooter?.isHidden = true
        webView.scrollView.delegate = self
        webView.allowsLinkPreview = false
        webView.uiDelegate = self
        webView.scrollView.backgroundColor = .groupTableViewBackground
        #if RELEASE
            webView.scrollView.showsHorizontalScrollIndicator = false
        #endif
        let states: [MJRefreshState] = [.idle, .pulling, .refreshing, .noMoreData]
        for state in states {
            webView.loadMoreFooter?.setTitle(viewModel.footerTitle(for: state), for: state)
        }
        webView.dataLoadDelegate = self
        webView.status = .loading
    }
    
    fileprivate func skinWebViewJavascriptBridge(_ bridge: WKWebViewJavascriptBridge) {
        bridge.registerHandler("userClicked") { [weak self] (data, _) in
            guard let `self` = self,
                let data = data,
                let user = try? User.decode(JSON(data)).dematerialize() else { return }
            self.perform(.userProfile) { userProfileVC in
                userProfileVC.user = user
            }
        }
        
        bridge.registerHandler("shouldImageAutoLoad") { [weak self] (_, callback) in
            self?.viewModel.shouldAutoLoadImage { autoLoad in
                callback?(autoLoad)
            }
        }
        
        bridge.registerHandler("linkActivated") { (data, _) in
            guard let data = data, let urlString = data as? String else { return }
            URLDispatchManager.shared.linkActived(PostViewModel.skinURL(url: urlString))
        }
        
        bridge.registerHandler("postClicked") { [weak self] (data, _) in
            guard let data = data,
                let dic = data as? [String: Int],
                let pid = dic["pid"],
                let uid = dic["uid"] else { return }
            self?.postClicked(pid: pid, uid: uid)
        }
        
        bridge.registerHandler("imageClicked") { [weak self] (data, _) in
            guard let data  = data,
                let dic = data as? [String: Any],
                let clickedImageURL = dic["clickedImageSrc"] as? String,
                let imageURLs = dic["imageSrcs"] as? [String] else { return }
            self?.imageClicked(clickedImageURL: clickedImageURL, imageURLs: imageURLs)
        }
        
        bridge.registerHandler("loadImage") { [weak self] (data, callback) in
            guard let data = data, let url = data as? String else { return }
            self?.viewModel.loadImage(url: url) { error in
                callback?(error == nil)
                if let error = error {
                    self?.showPromptInformation(of: .failure(error.localizedDescription))
                }
            }
        }
        
        bridge.registerHandler("imageLongPressed") { [weak self] (data, _) in
            guard let data = data, let url = data as? String else { return }
            self?.imageLongPressed(url: url)
        }
        
        if let pid =  postInfo.pid {
            bridge.callHandler("jumpToPid", data: pid)
        }
    }
}

// MARK: - Bridge Handler

extension PostViewController {
    fileprivate func postClicked(pid: Int, uid: Int) {
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        actionSheet.addAction(UIAlertAction(title: "回复", style: .default) { _ in
            
        })
        actionSheet.addAction(UIAlertAction(title: "引用", style: .default) { _ in
            
        })
        
        let look: UIAlertAction
        if let _ = viewModel.postInfo.authorid {
            look = UIAlertAction(title: "显示全部帖子", style: .default) { [unowned self] _ in
                let postInfo = PostInfo(tid: self.viewModel.postInfo.tid, page: 1, pid: nil, authorid: nil)
                self.viewModel.postInfo = postInfo
                self.webView.status = .loading
                self.loadData()
            }
        } else {
            look = UIAlertAction(title: "只看该作者", style: .default) { [unowned self] _ in
                let postInfo = PostInfo(tid: self.viewModel.postInfo.tid, page: 1, pid: nil, authorid: uid)
                self.viewModel.postInfo = postInfo
                self.webView.status = .loading
                self.loadData()
            }
        }
        actionSheet.addAction(look)
        
        if uid == Settings.shared.activeAccount?.uid {
            // FIXME: - 添加编辑功能
        }
    
        actionSheet.addAction(UIAlertAction(title: "取消", style: .cancel, handler: nil))
        
        present(actionSheet, animated: true, completion: nil)
    }
    
    fileprivate func imageClicked(clickedImageURL: String, imageURLs: [String]) {
        showImageBrowser(clickedImageURL: clickedImageURL, imageURLs: imageURLs)
    }
    
    fileprivate func imageLongPressed(url: String) {
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let look = UIAlertAction(title: "查看", style: .default) { [weak self] _ in
            self?.showImageBrowser(clickedImageURL: url, imageURLs: [url])
        }
        let copy = UIAlertAction(title: "复制", style: .default) { [weak self] _ in
            guard let `self` = self else { return }
            self.showPromptInformation(of: .loading("正在复制..."))
            ImageUtils.copyImage(url: url) { [weak self] (result) in
                self?.hidePromptInformation()
                switch result {
                case let .failure(error):
                    self?.showPromptInformation(of: .failure(error.localizedDescription))
                case .success(_):
                    self?.showPromptInformation(of: .success("复制成功！"))
                }
            }
        }
        let save = UIAlertAction(title: "保存", style: .default) { [weak self] _ in
            guard let `self` = self else { return }
            self.showPromptInformation(of: .loading("正在保存..."))
            ImageUtils.saveImage(url: url) { [weak self] (result) in
                self?.hidePromptInformation()
                switch result {
                case let .failure(error):
                    self?.showPromptInformation(of: .failure(error.localizedDescription))
                case .success(_):
                    self?.showPromptInformation(of: .success("保存成功！"))
                }
            }
        }
        let detectQrCode = UIAlertAction(title: "识别图中二维码", style: .default) { [weak self] _ in
            guard let `self` = self else { return }
            self.showPromptInformation(of: .loading("正在识别..."))
            ImageUtils.qrcode(from: url) { [weak self] result in
                self?.hidePromptInformation()
                switch result {
                case let .success(qrCode):
                    self?.showQrCode(qrCode)
                case let .failure(error):
                    self?.showPromptInformation(of: .failure(error.localizedDescription))
                }
            }
        }
        let cancel = UIAlertAction(title: "取消", style: .cancel, handler: nil)
        actionSheet.addAction(look)
        actionSheet.addAction(copy)
        actionSheet.addAction(save)
        actionSheet.addAction(detectQrCode)
        actionSheet.addAction(cancel)
        present(actionSheet, animated: true, completion: nil)
    }
    
    fileprivate func showQrCode(_ qrCode: String) {
        let actionSheet = UIAlertController(title: "识别二维码", message: "二维码内容为: \(qrCode)", preferredStyle: .actionSheet)
        let copy = UIAlertAction(title: "复制", style: .default) { _ in
            UIPasteboard.general.string = qrCode
        }
        var openLink: UIAlertAction!
        if qrCode.isLink {
            openLink = UIAlertAction(title: "打开链接", style: .default, handler: { _ in
                URLDispatchManager.shared.linkActived(qrCode)
            })
        }
        let cancel = UIAlertAction(title: "取消", style: .cancel, handler: nil)
        actionSheet.addAction(copy)
        if qrCode.isLink {
            actionSheet.addAction(openLink)
        }
        actionSheet.addAction(cancel)
        present(actionSheet, animated: true, completion: nil)
    }
}

// MARK: - Image Related

extension PostViewController {
    fileprivate func showImageBrowser(clickedImageURL: String, imageURLs: [String]) {
        guard let selectedIndex = imageURLs.index(of: clickedImageURL) else { return }
        let imageBrowser = ImageBrowserViewController.load(from: .views)
        imageBrowser.imageURLs = imageURLs
        imageBrowser.selectedIndex = selectedIndex
        imageBrowser.modalPresentationStyle = .custom
        imageBrowser.modalTransitionStyle = .crossDissolve
        imageBrowser.modalPresentationCapturesStatusBarAppearance = true
        present(imageBrowser, animated: true, completion: nil)
    }
}

// MARK: - DataLoadDelegate

extension PostViewController: DataLoadDelegate {
    private func dataLoadCompletion(_ result: PostResult) {
        updateWebViewState()
        handleDataLoadResult(result)
    }
    
    func loadData() {
        viewModel.loadData { [weak self] result in
            guard let `self` = self else { return }
            if !self.isLoading {
                self.isLoading = true
                self.skinRightBarButtonItems()
            }
            self.dataLoadCompletion(result)
        }
    }
    
    func loadNewData() {
        if !isLoading {
            isLoading = true
            skinRightBarButtonItems()
        }
        viewModel.loadNewData { [weak self] result in
            self?.skinRightBarButtonItems()
            self?.dataLoadCompletion(result)
        }
    }
    
    func loadMoreData() {
        if !isLoading {
            isLoading = true
            skinRightBarButtonItems()
        }
        viewModel.loadMoreData { [weak self] result in
            self?.skinRightBarButtonItems()
            self?.dataLoadCompletion(result)
        }
    }
}

// MARK: - UIScrollViewDelegate

extension PostViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return nil
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        #if RELEASE
            if scrollView.contentOffset.x > 0 || scrollView.contentOffset.x < 0 {
                scrollView.contentOffset = CGPoint(x: 0, y: scrollView.contentOffset.y)
            }
        #endif
    }
}

// MARK: - WKNavigationDelegate

extension PostViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.scrollView.backgroundColor = .groupTableViewBackground
        (webView as? BaseWebView)?.loadMoreFooter?.isHidden = false
        isLoading = false
        skinRightBarButtonItems()
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.navigationType == .linkActivated ? .cancel : .allow)
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleWebViewError(error)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleWebViewError(error)
    }
    
    private func handleWebViewError(_ error: Error) {
        #if DEBUG
            showPromptInformation(of: .failure(String(describing: error)))
        #else
            if (error as NSError).code != NSURLErrorCancelled {
                showPromptInformation(of: .failure(error.localizedDescription))
            }
        #endif
    }
}

// MARK: - WKUIDelegate

extension PostViewController: WKUIDelegate {
    @available(iOS 10.0, *)
    func webView(_ webView: WKWebView, shouldPreviewElement elementInfo: WKPreviewElementInfo) -> Bool {
        return false
    }
}

// MARK: - StoryboardLoadable

extension PostViewController: StoryboardLoadable {}

// MARK: - Segue Extesion

extension Segue {
    /// 查看个人资料
    fileprivate static var userProfile: Segue<UserProfileViewController> {
        return .init(identifier: "userProfile")
    }
}

// MARK: - Tools

private func ==<T: Equatable>(lhs: T?, rhs: T?) -> Bool {
    switch (lhs, rhs) {
    case let(l?, r?):
        return l == r
    case (nil, nil):
        return true
    default:
        return false
    }
}
