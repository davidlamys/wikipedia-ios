import WMF

protocol DetailPresentingFromContentGroup {
    var contentGroupIDURIString: String? { get }
}

@objc(WMFNavigationStateController)
final class NavigationStateController: NSObject {
    private let dataStore: MWKDataStore

    @objc init(dataStore: MWKDataStore) {
        self.dataStore = dataStore
        super.init()
    }

    private typealias ViewController = NavigationState.ViewController
    private typealias Presentation = ViewController.Presentation
    private typealias Info = ViewController.Info

    @objc func restoreNavigationState(for navigationController: UINavigationController, in moc: NSManagedObjectContext) {
        guard let tabBarController = navigationController.viewControllers.first as? UITabBarController else {
            assertionFailure("Expected root view controller to be UITabBarController")
            return
        }
        guard let navigationState = moc.navigationState else {
            return
        }
        WMFAuthenticationManager.sharedInstance.attemptLogin {
            for viewController in navigationState.viewControllers {
                self.restore(viewController: viewController, for: tabBarController, navigationController: navigationController, in: moc)
            }
        }
    }

    func allPreservedArticleKeys(in moc: NSManagedObjectContext) -> [String]? {
        return moc.navigationState?.viewControllers.compactMap { $0.info?.articleKey }
    }

    private func pushOrPresent(_ viewController: UIViewController, navigationController: UINavigationController, presentation: Presentation, animated: Bool = false) {
        switch presentation {
        case .push:
            navigationController.pushViewController(viewController, animated: animated)
        case .modal:
            navigationController.present(viewController, animated: animated)
        }
    }

    private func articleURL(from info: Info) -> URL? {
        guard
            let articleKey = info.articleKey,
            var articleURL = URL(string: articleKey)
        else {
            return nil
        }
        if let sectionAnchor = info.articleSectionAnchor, let articleURLWithFragment = articleURL.wmf_URL(withFragment: sectionAnchor) {
            articleURL = articleURLWithFragment
        }
        return articleURL
    }

    private func restore(viewController: ViewController, for tabBarController: UITabBarController, navigationController: UINavigationController, in moc: NSManagedObjectContext) {
        var newNavigationController: UINavigationController?

        if let info = viewController.info, let selectedIndex = info.selectedIndex {
            tabBarController.selectedIndex = selectedIndex
            switch tabBarController.selectedViewController {
            case let savedViewController as SavedViewController:
                guard let currentSavedViewRawValue = info.currentSavedViewRawValue else {
                    return
                }
                savedViewController.toggleCurrentView(currentSavedViewRawValue)
            case let searchViewController as SearchViewController:
                searchViewController.setSearchVisible(true, animated: false)
                searchViewController.searchTerm = info.searchTerm
                searchViewController.search()
            default:
                break
            }
        } else {
            switch (viewController.kind, viewController.info) {
            case (.random, let info?) :
                guard let articleURL = articleURL(from: info) else {
                    return
                }
                let randomArticleVC = WMFRandomArticleViewController(articleURL: articleURL, dataStore: dataStore, theme: Theme.standard)
                pushOrPresent(randomArticleVC, navigationController: navigationController, presentation: viewController.presentation)
            case (.article, let info?):
                guard let articleURL = articleURL(from: info) else {
                    return
                }
                let articleVC = WMFArticleViewController(articleURL: articleURL, dataStore: dataStore, theme: Theme.standard)
                pushOrPresent(articleVC, navigationController: navigationController, presentation: viewController.presentation)
            case (.themeableNavigationController, _):
                let themeableNavigationController = WMFThemeableNavigationController()
                pushOrPresent(themeableNavigationController, navigationController: navigationController, presentation: viewController.presentation)
                newNavigationController = themeableNavigationController
            case (.settings, _):
                let settingsVC = WMFSettingsViewController(dataStore: dataStore)
                pushOrPresent(settingsVC, navigationController: navigationController, presentation: viewController.presentation)
            case (.account, _):
                let accountVC = AccountViewController()
                accountVC.dataStore = dataStore
                pushOrPresent(accountVC, navigationController: navigationController, presentation: viewController.presentation)
            case (.talkPage, let info?):
                guard
                    let siteURLString = info.talkPageSiteURLString,
                    let siteURL = URL(string: siteURLString),
                    let title = info.talkPageTitle,
                    let typeRawValue = info.talkPageTypeRawValue,
                    let type = TalkPageType(rawValue: typeRawValue)
                else {
                    return
                }
                let talkPageContainerVC = TalkPageContainerViewController(title: title, siteURL: siteURL, type: type, dataStore: dataStore)
                talkPageContainerVC.apply(theme: Theme.standard)
                navigationController.isNavigationBarHidden = true
                navigationController.pushViewController(talkPageContainerVC, animated: false)
            case (.talkPageReplyList, let info?):
                guard
                    let talkPageTopic = managedObject(with: info.contentGroupIDURIString, in: moc) as? TalkPageTopic,
                    let talkPageContainerVC = navigationController.viewControllers.last as? TalkPageContainerViewController
                else {
                    return
                }
                talkPageContainerVC.pushToReplyThread(topic: talkPageTopic)
            case (.readingListDetail, let info?):
                guard let readingList = managedObject(with: info.readingListURIString, in: moc) as? ReadingList else {
                    return
                }
                let readingListDetailVC =  ReadingListDetailViewController(for: readingList, with: dataStore)
                pushOrPresent(readingListDetailVC, navigationController: navigationController, presentation: viewController.presentation)
            case (.detail, let info?):
                guard
                    let contentGroup = managedObject(with: info.contentGroupIDURIString, in: moc) as? WMFContentGroup,
                    let detailVC = contentGroup.detailViewControllerWithDataStore(dataStore, theme: Theme.standard)
                else {
                    return
                }
                pushOrPresent(detailVC, navigationController: navigationController, presentation: viewController.presentation)
            default:
                return
            }
        }

        for child in viewController.children {
            restore(viewController: child, for: tabBarController, navigationController: newNavigationController ?? navigationController, in: moc)
        }
    }

    private func managedObject<T: NSManagedObject>(with uriString: String?, in moc: NSManagedObjectContext) -> T? {
        guard
            let uriString = uriString,
            let uri = URL(string: uriString),
            let id = moc.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: uri),
            let object = try? moc.existingObject(with: id) as? T
        else {
            return nil
        }
        return object
    }

    @objc func saveNavigationState(for navigationController: UINavigationController, in moc: NSManagedObjectContext) {
        var viewControllers = [ViewController]()
        for viewController in navigationController.viewControllers {
            viewControllers.append(contentsOf: viewControllersToSave(from: viewController, presentedVia: .push))
        }
        moc.navigationState = NavigationState(viewControllers: viewControllers)
    }

    private func viewControllerToSave(from viewController: UIViewController, presentedVia presentation: Presentation) -> ViewController? {
        let kind: ViewController.Kind?
        let info: Info?

        switch viewController {
        case let tabBarController as UITabBarController:
            kind = .tab
            switch tabBarController.selectedViewController {
            case let savedViewController as SavedViewController:
                info = Info(selectedIndex: tabBarController.selectedIndex, currentSavedViewRawValue: savedViewController.currentView.rawValue)
            case let searchViewController as SearchViewController:
                info = Info(selectedIndex: tabBarController.selectedIndex, searchTerm: searchViewController.searchTerm)
            default:
                info = Info(selectedIndex: tabBarController.selectedIndex)
            }
        case is WMFThemeableNavigationController:
            kind = .themeableNavigationController
            info = nil
        case is WMFSettingsViewController:
            kind = .settings
            info = nil
        case let articleViewController as WMFArticleViewController:
            kind = viewController is WMFRandomArticleViewController ? .random : .article
            info = Info(articleKey: articleViewController.articleURL.wmf_articleDatabaseKey, articleSectionAnchor: articleViewController.visibleSectionAnchor)
        case let talkPageContainerVC as TalkPageContainerViewController:
            kind = .talkPage
            info = Info(talkPageSiteURLString: talkPageContainerVC.siteURL.absoluteString, talkPageTitle: talkPageContainerVC.talkPageTitle, talkPageTypeRawValue: talkPageContainerVC.type.rawValue)
        case let talkPageReplyListVC as TalkPageReplyListViewController:
            kind = .talkPageReplyList
            info = Info(talkPageTopicURIString: talkPageReplyListVC.topic.objectID.uriRepresentation().absoluteString)
        case let readingListDetailVC as ReadingListDetailViewController:
            kind = .readingListDetail
            info = Info(readingListURIString: readingListDetailVC.readingList.objectID.uriRepresentation().absoluteString)
        case let detailPresenting as DetailPresentingFromContentGroup:
            kind = .detail
            info = Info(contentGroupIDURIString: detailPresenting.contentGroupIDURIString)
        default:
            kind = nil
            info = nil
        }

        return ViewController(kind: kind, presentation: presentation, info: info)
    }

    private func viewControllersToSave(from viewController: UIViewController, presentedVia presentation: Presentation) -> [ViewController] {
        var viewControllers = [ViewController]()
        if var viewControllerToSave = viewControllerToSave(from: viewController, presentedVia: presentation) {
            if let presentedViewController = viewController.presentedViewController {
                viewControllerToSave.updateChildren(viewControllersToSave(from: presentedViewController, presentedVia: .modal))
            }
            if let navigationController = viewController as? UINavigationController {
                var children = [ViewController]()
                for viewController in navigationController.viewControllers {
                    children.append(contentsOf: viewControllersToSave(from: viewController, presentedVia: .push))
                }
                viewControllerToSave.updateChildren(children)
            }
            viewControllers.append(viewControllerToSave)
        }
        return viewControllers
    }
}
