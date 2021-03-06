//
//  MainTableViewController.swift
//  sample-conference-videochat-swift
//
//  Created by Vladimir Nybozhinsky on 11.10.2018.
//  Copyright © 2018 QuickBlox. All rights reserved.
//

import UIKit
import SVProgressHUD
import Quickblox
import QuickbloxWebRTC

struct MainSegueConstant {
    static let settings = "PresentSettingsViewController"
    static let users = "PresentUsersViewController"
    static let call = "PresentCallViewController"
    static let sceneAuth = "SceneSegueAuth"
}

struct MainAlertConstant {
    static let checkInternet = NSLocalizedString("Please check your Internet connection", comment: "")
    static let okAction = NSLocalizedString("Ok", comment: "")
    static let logout = NSLocalizedString("Logout...", comment: "")
}

struct CallSettings {
    var conferenseType: QBRTCConferenceType?
    var chatDialog: QBChatDialog
}

class MainTableViewController: UITableViewController {
    //MARK: Properties
    let core = Core.instance
    
    lazy private var dialogsDataSource: DialogsDataSource = {
        let dialogsDataSource = DialogsDataSource.init()
        return dialogsDataSource
    }()
    
    lazy private var usersDataSource: UsersDataSource = {
        let usersDataSource = UsersDataSource()
        return usersDataSource
    }()
    
    // MARK: Life Cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        core.addDelegate(self)
        
        // Reachability
        core.networkStatusBlock = { [weak self] status in
            if status != NetworkConnectionStatus.notConnection {
                self?.fetchData()
            }
        }
        
        configureNavigationBar()
        configureTableViewController()
        fetchData()
        
        // adding refresh control task
        if let refreshControl = self.refreshControl {
            refreshControl.addTarget(self, action: #selector(fetchData), for: .valueChanged)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let refreshControl = self.refreshControl, refreshControl.isRefreshing == true {
            let contentOffset = CGPoint(x: 0.0, y: -refreshControl.frame.size.height)
            tableView.setContentOffset(contentOffset, animated: false)
        }
    }
    
    deinit {
        debugPrint("deinit \(self)")
    }
    
    // MARK: - Setup
    private func configureTableViewController() {
        dialogsDataSource.delegate = self
        tableView.dataSource = dialogsDataSource
        tableView.rowHeight = 76.0
        refreshControl?.beginRefreshing()
    }
    
    private func configureNavigationBar() {
        let settingsButtonItem = UIBarButtonItem(image: UIImage(named: "ic-settings"),
                                                 style: .plain,
                                                 target: self,
                                                 action: #selector(didTapSettingsButton(_:)))
        navigationItem.leftBarButtonItem = settingsButtonItem
        
        let usersButtonItem = UIBarButtonItem(image: UIImage(named: "new-message"),
                                              style: .plain,
                                              target: self,
                                              action: #selector(didPressUsersButton(_:)))
        navigationItem.rightBarButtonItem = usersButtonItem
        showInfoButton()
        
        //Custom label
        var userName = "Logged in as "
        var roomName = ""
        var titleString = ""
        if let currentUser = core.currentUser,
            let fullname = currentUser.fullName,
            let tags = currentUser.tags,
            tags.isEmpty == false,
            let name = tags.first {
            roomName = name
            userName = userName + fullname
            titleString = roomName + "\n" + userName
        }
        
        let attrString = NSMutableAttributedString(string: titleString)
        let roomNameRange: NSRange = (titleString as NSString).range(of: roomName )
        attrString.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: 16.0), range: roomNameRange)
        
        let userNameRange: NSRange = (titleString as NSString).range(of: userName)
        attrString.addAttribute(.font, value: UIFont.systemFont(ofSize: 12.0), range: userNameRange)
        attrString.addAttribute(.foregroundColor, value: UIColor.gray, range: userNameRange)
        
        let titleView = UILabel(frame: CGRect.zero)
        titleView.numberOfLines = 2
        titleView.attributedText = attrString
        titleView.textAlignment = .center
        titleView.sizeToFit()
        
        navigationItem.titleView = titleView
    }
    
    // MARK: - Internal Methods
    private func hasConnectivity() -> Bool {
        let status = core.networkConnectionStatus()
        guard status != NetworkConnectionStatus.notConnection else {
            showAlertView(message: MainAlertConstant.checkInternet)
            return false
        }
        return true
    }
    
    private func showAlertView(message: String?) {
        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: MainAlertConstant.okAction, style: .default,
                                                handler: nil))
        present(alertController, animated: true)
    }
    
    @objc private func fetchData() {
        let dataGroup = DispatchGroup()
        
        dataGroup.enter()
        DataFetcher.fetchDialogs({ [weak self] dialogs in
            dataGroup.leave()
            guard dialogs.isEmpty == false else {
                return
            }
            self?.dialogsDataSource.updateObjects(dialogs)
            self?.tableView.reloadData()
            }, failure: { [weak self] (description) in
                self?.showAlertView(message: description)
        })
        
        dataGroup.enter()
        DataFetcher.fetchUsers({ [weak self] users in
            dataGroup.leave()
            self?.usersDataSource.updateObjects(users)
            }, failure: { [weak self] (description) in
                self?.showAlertView(message: description)
        })
        
        dataGroup.notify(queue: DispatchQueue.main) {
            self.refreshControl?.endRefreshing()
        }
    }
    
    //MARK: - Actions
    @objc func didTapSettingsButton(_ item: UIBarButtonItem?) {
        performSegue(withIdentifier: MainSegueConstant.settings, sender: item)
    }
    
    @objc func didPressUsersButton(_ item: UIBarButtonItem?) {
        performSegue(withIdentifier: MainSegueConstant.users, sender: item)
    }
    
    //MARK: - Overrides
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        switch segue.identifier {
        case MainSegueConstant.settings:
            let settingsViewController = (segue.destination as? UINavigationController)?.topViewController
                as? SessionSettingsViewController
            settingsViewController?.delegate = self
            
        case MainSegueConstant.users:
            let usersViewController = segue.destination as? UsersViewController
            usersViewController?.dataSource = usersDataSource
            usersViewController?.delegate = self
            
        case MainSegueConstant.call:
            guard let settings = sender as? CallSettings else {
                return
            }
            let callViewController = segue.destination as? CallViewController
            callViewController?.chatDialog = settings.chatDialog
            callViewController?.conferenceType = settings.conferenseType
            callViewController?.dataSource = usersDataSource
            
        default:
            break
        }
    }
}

extension MainTableViewController: UsersViewControllerDelegate {
    // MARK: UsersViewControllerDelegate
    func usersViewController(_ usersViewController: UsersViewController,
                             didCreateChatDialog chatDialog: QBChatDialog) {
        dialogsDataSource.addObjects([chatDialog])
        tableView.reloadData()
    }
    
}

extension MainTableViewController: SettingsViewControllerDelegate {
    // MARK: SettingsViewControllerDelegate
    func settingsViewController(_ vc: SessionSettingsViewController, didPressLogout sender: Any) {
        SVProgressHUD.show(withStatus: MainAlertConstant.logout)
        core.logout()
    }
}

extension MainTableViewController: CoreDelegate {
    // MARK: CoreDelegate
    func coreDidLogin(_ core: Core) {
        SVProgressHUD.dismiss()
    }
    
    func coreDidLogout(_ core: Core) {
        SVProgressHUD.dismiss()
        //Dismiss Settings view controller
        dismiss(animated: false)
        DispatchQueue.main.async(execute: {
            self.performSegue(withIdentifier: MainSegueConstant.sceneAuth, sender: nil)
        })
    }
    
    func core(_ core: Core, loginStatus: String) {
        debugPrint("coreDidLogin")
    }
    
    func core(_ core: Core, error: Error, domain: ErrorDomain) {
        guard domain == ErrorDomain.logOut else {
            return
        }
        SVProgressHUD.showError(withStatus: error.localizedDescription)
    }
}

extension MainTableViewController: DialogsDataSourceDelegate {
    //MARK: - DialogsDataSourceDelegate
    func dataSource(_ dataSource: DialogsDataSource,
                    didTapListenerAtCell cell: UITableViewCell) {
        joinDialog(cell, conferenceType: nil)
    }
    
    func dataSource(_ dataSource: DialogsDataSource,
                    didTapAudioAtCell cell: UITableViewCell) {
        joinDialog(cell, conferenceType: QBRTCConferenceType.audio)
    }
    
    func dataSource(_ dataSource: DialogsDataSource,
                    didTapVideoAtCell cell: UITableViewCell) {
        joinDialog(cell, conferenceType: QBRTCConferenceType.video)
    }
    
    func dataSource(_ dataSource: DialogsDataSource,
                    commit editingStyle: UITableViewCell.EditingStyle,
                    forRowAt indexPath: IndexPath) {
        if editingStyle != .delete,
            hasConnectivity() != true  {
            return
        }
        
        let dialog = dataSource.objects[indexPath.row]
        
        guard let dialogId = dialog.id else {
            return
        }
        
        SVProgressHUD.show()
        
        QBRequest.deleteDialogs(withIDs: [dialogId],
                                forAllUsers: false,
                                successBlock: { [weak self] response,
                                    deletedObjectsIDs,
                                    notFoundObjectsIDs,
                                    wrongPermissionsObjectsIDs in
                                    guard let `self` = self else {
                                        return
                                    }
                                    //remove deleted dialog from datasource
                                    let dialogs = self.dialogsDataSource.objects
                                    let filteredDialogs = dialogs.filter({$0 != dialog})
                                    self.dialogsDataSource.updateObjects(filteredDialogs)
                                    self.tableView.reloadData()
                                    SVProgressHUD.dismiss()
            }, errorBlock: { response in
                SVProgressHUD.showError(withStatus: "\(String(describing: response.error?.reasons))")
        })
    }
    
    // MARK: - Internal Methods
    private func joinDialog(_ cell: UITableViewCell, conferenceType: QBRTCConferenceType?) {
        guard hasConnectivity() == true,
            let indexPath = tableView.indexPath(for: cell) else {
                return
        }
        
        let chatDialog = dialogsDataSource.objects[indexPath.row]
        let callSettings = CallSettings(conferenseType: conferenceType, chatDialog: chatDialog)
        
        if let conferenceType = conferenceType {
            CallPermissions.check(with: conferenceType) { [weak self] granted in
                guard granted == true else { return }
                self?.performSegue(withIdentifier: MainSegueConstant.call,
                                   sender: callSettings)
            }
        } else {
            // will join to conferences as the listener
            self.performSegue(withIdentifier: MainSegueConstant.call,
                              sender: callSettings)
        }
    }
    
}
