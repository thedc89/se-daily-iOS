//
//  CommentsViewController.swift
//  SEDaily-IOS
//
//  Created by jason on 1/31/18.
//  Copyright © 2018 Koala Tea. All rights reserved.
//

import UIKit
import Down
class CommentsViewController: UIViewController {

    @IBOutlet var headerView: ThreadHeaderView!

    @IBOutlet weak var closeStatusAreaButton: UIButton!
    @IBOutlet weak var createCommentHeight: NSLayoutConstraint!
    @IBOutlet weak var createCommentHolder: UIView!
    @IBOutlet weak var composeStatusLabel: UILabel!
    
    @IBOutlet weak var composeStatusHolder: UIStackView!
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var heightOfReplyInfoHolder: NSLayoutConstraint!
   
    private let refreshControl = UIRefreshControl()
    var rootEntityId: String?
    var thread: ForumThread?
    
    let networkService = API()
    var comments: [Comment] = [] {
        didSet {
            if comments.count == 0 {
                // Still show if thread is defined because that means we'll have a header:
                if thread != nil {
                    tableView.isHidden = false
                } else {
                    tableView.isHidden = true
                }
            } else {
                tableView.isHidden = false
            }
        }
    }
    
    // Constraints on Comment Holder
    @IBOutlet weak var bottomCommentTextField: NSLayoutConstraint!
    @IBOutlet weak var topStatusHolder: NSLayoutConstraint!
    @IBOutlet weak var topCreateCommentTextField: NSLayoutConstraint!
    @IBOutlet weak var heightCreateCommentTextField: NSLayoutConstraint!
    @IBOutlet weak var heightReplyInfoHolder: NSLayoutConstraint!
    
    // This is set when user clicks on reply
    var parentCommentSelected: Comment? {
        didSet {
            guard let parentComment = parentCommentSelected else {
                // Hide
                composeStatusHolder.isHidden = true
                heightOfReplyInfoHolder.constant = 0
                self.view.layoutIfNeeded()
                return
            }
            
            // Show  the reply area
            if let replyTo = parentComment.author.username {
                composeStatusLabel.text = "Reply to: \(replyTo)"
            } else {
                composeStatusLabel.text = "Reply to: \(parentComment.content)"
            }
            
            composeStatusHolder.isHidden = false
            heightOfReplyInfoHolder.constant = 50
            view.layoutIfNeeded()
        }
    }
    
    @IBOutlet weak var createCommentTextField: UITextField!
    @IBOutlet weak var submitCommentButton: UIButton!
    
    let activityIndicator: UIActivityIndicatorView = UIActivityIndicatorView()
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.dataSource = self
        tableView.delegate = self
      
        title = L10n.comments
        // Hide the reply area
        composeStatusHolder.isHidden = true
        heightOfReplyInfoHolder.constant = 0
        self.view.layoutIfNeeded()
    
        // Add activity indicator / spinner
        activityIndicator.center = self.view.center
        activityIndicator.hidesWhenStopped = true
        activityIndicator.activityIndicatorViewStyle = UIActivityIndicatorViewStyle.gray
        view.addSubview(activityIndicator)
        
        if let thread = thread {
            setupTableHeader(thread: thread)
        }
        
        updateUIBasedOnUser()
        
        // Style (x) close button for status area:
        let iconSize = UIView.getValueScaledByScreenHeightFor(baseValue: 20)
        closeStatusAreaButton.setIcon(icon: .fontAwesome(.times), iconSize: iconSize, color: Stylesheet.Colors.offBlack, forState: .normal)
        
        loadComments()
        setupPullToRefresh()
    }
    
    func updateUIBasedOnUser () {
        // Hide if user is not logged in OR if user is limited (no true username)
        if !isFullUser() {
            // TODO: setting the table view footer would make make this much easier.
            // Constraints:
            bottomCommentTextField.isActive = false
            topStatusHolder.isActive = false
            topCreateCommentTextField.isActive = false
            heightCreateCommentTextField.isActive = false
            heightReplyInfoHolder.isActive = false
            
            //
            createCommentHeight.constant = 0
            createCommentHolder.isHidden = true
            self.view.layoutSubviews()
        }
    }
    
    func setupPullToRefresh () {
        // Setup pull down to refresh
        if #available(iOS 10.0, *) {
            tableView.refreshControl = refreshControl
        } else {
            tableView.addSubview(refreshControl)
        }
        refreshControl.addTarget(self, action: #selector(refreshListData(_:)), for: .valueChanged)
    }
    
    @objc private func refreshListData(_ sender: Any) {
        // Fetch Weather Data
        loadComments()
    }

    func setupTableHeader (thread: ForumThread) {
        headerView.thread = thread
        tableView.tableHeaderView = headerView
        headerView.setNeedsLayout()
        headerView.layoutIfNeeded()
        
        let height = headerView.systemLayoutSizeFitting(UILayoutFittingCompressedSize).height
        var frame = headerView.frame
        frame.size.height = height
        headerView.frame = frame
        
        tableView.tableHeaderView = headerView
    }
 
    // Should be in the model but only used by comments for now:
    func isFullUser() -> Bool {
        if !UserManager.sharedInstance.isCurrentUserLoggedIn() {
            return false
        }
               
        return true
       
    }

    func loadComments() {
        activityIndicator.startAnimating()
        
        guard let rootEntityId = rootEntityId else {
               composeStatusLabel.text = L10n.thereWasAProblem
            return
        }
        networkService.getComments(rootEntityId: rootEntityId, onSuccess: { [weak self] (comments) in
            guard let flatComments = self?.flattenComments(nestedComments: comments) else {
                self?.composeStatusLabel.text = L10n.thereWasAProblem
                return
            }
            self?.comments = flatComments
            self?.tableView.reloadData()
            self?.activityIndicator.stopAnimating()
            self?.refreshControl.endRefreshing()
            }, onFailure: { [weak self] (_) in
            self?.activityIndicator.stopAnimating()
            self?.composeStatusLabel.text = L10n.thereWasAProblem
        })
    }

    func flattenComments(nestedComments: [Comment]) -> [Comment] {
        var flatComments: [Comment] = []
        for nestedComment in nestedComments {
            flatComments.append(nestedComment)
            if let replies = nestedComment.replies {
                for reply in replies {
                    flatComments.append(reply)
                }
            }
        }
        return flatComments
    }
    
    @IBAction func submitCommentPressed(_ sender: UIButton) {
        self.view.endEditing(true) // Hide keyboard
        
        // Show Reply info holder (so we can use it to display statuses)
        composeStatusLabel.text = L10n.submitting
        composeStatusHolder.isHidden = false
        heightOfReplyInfoHolder.constant = 50
        self.view.layoutIfNeeded()
        
        // Disable text field:
        createCommentTextField.isUserInteractionEnabled = false
        submitCommentButton.isEnabled = false
        
        guard let rootEntityId = rootEntityId, let commentContent = createCommentTextField.text else {
            composeStatusLabel.text = L10n.thereWasAProblem
            return
        }
        networkService.createComment(rootEntityId: rootEntityId, parentComment: parentCommentSelected, commentContent: commentContent, onSuccess: { [weak self] in

            // Reset input field + re-enable button:
            self?.createCommentTextField.text = ""
            self?.createCommentTextField.isUserInteractionEnabled = true
            self?.submitCommentButton.isEnabled = true
            
            self?.composeStatusLabel.text = L10n.succcessfullySubmitted
            self?.parentCommentSelected = nil
            self?.loadComments()
        }, onFailure: { [weak self] (_) in
            self?.composeStatusLabel.text = L10n.thereWasAProblem
            self?.submitCommentButton.isEnabled = true
            self?.createCommentTextField.isUserInteractionEnabled = true
        })
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @IBAction func cancelReplyPressed(_ sender: UIButton) {
        parentCommentSelected = nil
    }
}

extension CommentsViewController: CommentReplyTableViewCellDelegate {
    func replyToCommentPressed(comment: Comment) {
        parentCommentSelected = comment
        createCommentTextField.becomeFirstResponder()
    }
}

extension CommentsViewController: UITableViewDelegate, UITableViewDataSource {
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // Sections and rows? comments and replies, neat idea
        return comments.count
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let comment = comments[indexPath.row]
        
        if comment.parentComment != nil {
            let cell = tableView.dequeueReusableCell(withIdentifier: "replyCell", for: indexPath) as? CommentReplyTableViewCell
            cell?.comment = comment
            return cell!
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "commentCell", for: indexPath) as? CommentTableViewCell
            cell?.delegate = self
            cell?.hideReplyCell = !isFullUser()
            cell?.comment = comment
            return cell!
        }
    }
    
    public func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
}
