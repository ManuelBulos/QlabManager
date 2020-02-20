//  ViewController.swift

import UIKit

class ViewController: UIViewController {

    @IBOutlet weak var serversTableView: UITableView!
    @IBOutlet weak var cuesTableView: UITableView!
    @IBOutlet weak var connectionLabel: UILabel!
    @IBOutlet weak var stopSelectedCueButton: UIButton!
    
    lazy var shadow: UIView = {
        let shadow = UIView(frame: .zero)
        shadow.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        return shadow
    }()
    
    let automaticConnection: Bool = true
    let refreshInterval: Double = 3
    
    let qlabPORT: Int = 53000
    let qlabIP: String = "10.0.1.111"
    let serverName: String = "Museo"
    
    var browser: QLKBrowser = QLKBrowser()
    var workspacesArray: [QLKWorkspace] = [QLKWorkspace]() // All workspaces in our server
    var currentWorkspace: QLKWorkspace? // Current connected workspace
    var selectedCue: QLKCue? // Selected cue from tableview
    var currentCue: QLKCue? // Current cue that is still playing
    
    var userDisconnectedManually: Bool = false // Flag to know if user should connect automatically to the first workspace when there is only one in the list
    
    override func viewDidLoad() {
        super.viewDidLoad()
        addObserverForCueUpdates()
        setupConnectionToServer()
        configureTableViews()
        view.addSubview(shadow)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        shadow.frame = CGRect(x: cuesTableView.frame.minX - 8, y: 0, width: cuesTableView.frame.width + 48, height: view.bounds.height)
    }
    
    func configureTableViews() {
        serversTableView.backgroundColor = .gray
        cuesTableView.backgroundColor = .gray
    }
    
    func setupConnectionToServer() {
        if automaticConnection {
            browser.delegate = self
            browser.start()
            browser.enableAutoRefresh(withInterval: refreshInterval)
        } else {
            let server = QLKServer.init(host: qlabIP, port: qlabPORT)
            server.name = serverName
            server.refreshWorkspaces { (workspaces) in
                self.workspacesArray = workspaces
                self.serversTableView.reloadData()
            }
        }
    }
    
    func addObserverForCueUpdates() {
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self,
                                       selector: #selector(handleCueUpdated(_:)),
                                       name: NSNotification.Name.QLKCueUpdated,
                                       object: nil)
    }
    
    @objc func handleCueUpdated(_ notification: Notification) {
        guard
            let _ = notification.object,
            let cuesTableView = cuesTableView
            else { return }
        NSObject.cancelPreviousPerformRequests(withTarget: cuesTableView,
                                               selector: #selector(cuesTableView.reloadData),
                                               object: nil)
        cuesTableView.perform(#selector(cuesTableView.reloadData), with: nil, afterDelay: 0.05)
    }
    
    func updateView() {
        cleanCurrentCueData()
        workspacesArray.removeAll()
        
        for server in browser.servers {
            self.workspacesArray.append(contentsOf: server.workspaces)
        }
        
        serversTableView.reloadData()
        
        if workspacesArray.count == 1 && !userDisconnectedManually {
            currentWorkspace = workspacesArray[0]
            connectToWorkspace(currentWorkspace)
        }
    }
    
    func disconnectFromWorkspace(_ workspace: QLKWorkspace?) {
        cleanCurrentCueData()
        currentWorkspace?.disconnect()
        currentWorkspace = nil
        connectionLabel.text = ""
        cuesTableView.reloadData()
        shadow.isHidden = false
    }
    
    func userSelectedWorkspaceFromList(indexPath: IndexPath) {
        if currentWorkspace != nil {
            showDisconnectAlert { (shouldDisconnect) in
                shouldDisconnect ? self.setCurrentWorkspace(indexPath: indexPath) : ()
            }
        } else {
            self.setCurrentWorkspace(indexPath: indexPath)
        }
    }
    
    func setCurrentWorkspace(indexPath: IndexPath) {
        if workspacesArray.isEmpty { showNoWorkspacesAlert(); return }
        disconnectFromWorkspace(currentWorkspace)
        currentWorkspace = workspacesArray[indexPath.row]
        connectToWorkspace(currentWorkspace)
    }
    
    func connectToWorkspace(_ workspace: QLKWorkspace?) {
        workspace?.connect(withPasscode: nil) { (data) in
            self.shadow.isHidden = true
            self.userDisconnectedManually = false
            self.connectionLabel.text = "Connected: " + ((workspace?.fullName) ?? "")
        }
    }
    
    func startWorkspaceWithCue(_ cue: QLKCue) {
        currentCue = cue
        currentWorkspace?.start(cue)
        setDurationTimerObserverForCue(cue)
    }
    
    func setDurationTimerObserverForCue(_ cue: QLKCue) {
        currentWorkspace?.cue(cue, valueForKey: QLKOSCDurationKey, block: { (duration) in
            guard let cueDuration = duration as? Float64 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(Int(cueDuration)), execute: {
                self.handleCueFinished(cue)
            })
        })
    }
    
    func handleCueFinished(_ cue: QLKCue) {
        if cue == currentCue { cleanCurrentCueData() }
    }
    
    func cleanCurrentCueData() {
        currentCue = nil
    }
    
    func getCuesArrayForCurrentWorkspace() -> [QLKCue]? {
        let cueList = currentWorkspace?.firstCueList
        return cueList?.property(forKey: QLKOSCCuesKey) as? [QLKCue]
    }
    
    @IBAction func goButtonPressed(_ sender: UIButton) {
        let row = cuesTableView.indexPathForSelectedRow?.row ?? 0
        let cuesArray = getCuesArrayForCurrentWorkspace()
        if cuesArray?.isEmpty ?? true {
            showNoCuesAlert()
        } else {
            guard let cue = cuesArray?[row] else {
                if let firstCue = cuesArray?.first {
                    startWorkspaceWithCue(firstCue)
                } else {
                    showNoCuesAlert()
                }
                return
            }
            startWorkspaceWithCue(cue)
        }
    }
    
    @IBAction func stopAllButtonPressed(_ sender: UIButton) {
        currentWorkspace?.stopAll()
        cleanCurrentCueData()
    }
    
    @IBAction func stopSelectedCueButtonPressed(_ sender: UIButton) {
        selectedCue?.stop()
        if selectedCue == currentCue { cleanCurrentCueData() }
    }
    
    @IBAction func stopCurrentCueButtonPressed(_ sender: UIButton) {
        currentCue?.stop()
        cleanCurrentCueData()
    }
    
    @IBAction func updateButtonPressed(_ sender: UIButton) {
        cuesTableView.reloadData()
    }
    
    @IBAction func disconnectButtonPressed(_ sender: UIButton) {
        showDisconnectAlert { (shouldDisconnect) in
            self.disconnectFromWorkspace(self.currentWorkspace)
            self.userDisconnectedManually = true
        }
    }

}

extension ViewController: QLKBrowserDelegate {
    func browserDidUpdateServers(_ browser: QLKBrowser) {
        updateView()
    }
    
    func browserServerDidUpdateWorkspaces(_ server: QLKServer) {
        updateView()
    }
}

extension ViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView == serversTableView {
            userSelectedWorkspaceFromList(indexPath: indexPath)
        } else {
            let cuesArray = getCuesArrayForCurrentWorkspace()
            selectedCue = cuesArray?[indexPath.row]
        }
    }
}

extension ViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView == serversTableView {
            return workspacesArray.count
        } else {
            return getCuesArrayForCurrentWorkspace()?.count ?? 0
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell()
        cell.textLabel?.font = UIFont.systemFont(ofSize: 40)
        cell.textLabel?.adjustsFontSizeToFitWidth = true
        cell.backgroundColor = .lightGray
        if tableView == serversTableView {
            let workspace = workspacesArray[indexPath.row]
            cell.textLabel?.text = workspace.name.uppercased()
        } else {
            let cue = getCuesArrayForCurrentWorkspace()?[indexPath.row]
            let numberText = "#" + (cue?.number ?? "")
            let nameText = " " + (cue?.listName ?? "")
            cell.textLabel?.text = numberText + nameText
        }
        return cell
    }
}

extension ViewController {
    func showNoCuesAlert() {
        let alert = UIAlertController(title: "Empty Workspace", message: "The selected worskpace contains no cues", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        self.present(alert, animated: true, completion: nil)
    }
    
    func showNoWorkspacesAlert() {
        let alert = UIAlertController(title: "Empty Server", message: "The selected server contains no workspaces", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .cancel))
        self.present(alert, animated: true, completion: nil)
    }
    
    func showDisconnectAlert(completion: @escaping (Bool) -> Void) {
        guard let workspaceName = currentWorkspace?.name else {completion(false); return}
        let alert = UIAlertController(title: "Close connection", message: "Are you sure you want to disconnect from \(workspaceName)?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Disconnect", style: .default, handler: { (_) in
            completion(true)
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (_) in
            completion(false)
        }))
        self.present(alert, animated: true, completion: nil)
    }
}
