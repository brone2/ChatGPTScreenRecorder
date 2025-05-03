import UIKit
import PhotosUI
import ReplayKit
/// MARK: - Models & Enums
enum MessageSender {
    case user
    case bot
}
enum MessageKind {
    /// text + multiple images in one bubble
    case combined(text: String?, images: [UIImage])
    /// special case for "typing..."
    case typingIndicator
}
/// Our chat message, storing who (user/bot) + content
struct ChatMessage {
    let sender: MessageSender
    let kind: MessageKind
}
/// MARK: - ChatMessageCell
class ChatMessageCell: UITableViewCell {
    static let identifier = "ChatMessageCell"
    
    private let bubbleView = UIView()
    private let messageLabel = UILabel()
    private let imageStack = UIStackView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    
    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .white
        
        // Bubble container
        bubbleView.layer.cornerRadius = 12
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bubbleView)
        
        // Label
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.addSubview(messageLabel)
        
        // Vertical stack for images
        imageStack.axis = .vertical
        imageStack.alignment = .leading
        imageStack.spacing = 4
        imageStack.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.addSubview(imageStack)
        
        // Spinner for typing indicator
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.addSubview(spinner)
        
        // Bubble constraints
        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            // up to 70% width
            bubbleView.widthAnchor.constraint(lessThanOrEqualTo: contentView.widthAnchor, multiplier: 0.70)
        ])
        
        leadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8)
        trailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8)
        
        // messageLabel constraints
        NSLayoutConstraint.activate([
            messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 8),
            messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 10),
            messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -10)
        ])
        
        // imageStack below label
        NSLayoutConstraint.activate([
            imageStack.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 6),
            imageStack.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 10),
            imageStack.trailingAnchor.constraint(lessThanOrEqualTo: bubbleView.trailingAnchor, constant: -10)
        ])
        
        // spinner
        NSLayoutConstraint.activate([
            spinner.topAnchor.constraint(equalTo: imageStack.bottomAnchor, constant: 8),
            spinner.centerXAnchor.constraint(equalTo: bubbleView.centerXAnchor),
            spinner.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -8)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }
    
    func configure(with message: ChatMessage) {
        leadingConstraint.isActive = false
        trailingConstraint.isActive = false
        
        // user => bubble on right, bot => bubble on left
        switch message.sender {
        case .user:
            bubbleView.backgroundColor = UIColor(white: 0.9, alpha: 1)
            trailingConstraint.isActive = true
            messageLabel.textAlignment = .left
        case .bot:
            bubbleView.backgroundColor = .white
            leadingConstraint.isActive = true
            messageLabel.textAlignment = .left
        }
        
        // reset label & spinner
        messageLabel.text = ""
        messageLabel.isHidden = true
        spinner.stopAnimating()
        
        // clear old images from stack
        for sub in imageStack.arrangedSubviews {
            imageStack.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }
        
        switch message.kind {
        case .typingIndicator:
            spinner.startAnimating()
            
        case .combined(let text, let images):
            if let t = text, !t.isEmpty {
                messageLabel.text = t
                messageLabel.isHidden = false
            }
            if !images.isEmpty {
                for img in images {
                    let iv = UIImageView(image: img)
                    iv.contentMode = .scaleAspectFill
                    iv.clipsToBounds = true
                    iv.layer.cornerRadius = 8
                    iv.translatesAutoresizingMaskIntoConstraints = false
                    iv.heightAnchor.constraint(lessThanOrEqualToConstant: 200).isActive = true
                    imageStack.addArrangedSubview(iv)
                }
            }
        }
    }
}
/// MARK: - ChatViewController
class ChatViewController: UIViewController {
    
    // Table
    private let tableView = UITableView()
    
    // Container for text input & buttons
    private let inputContainer = UIView()
    private let inputTextView = UITextView()
    private let buttonsContainer = UIStackView()
    
    // Our buttons
    private let uploadImageButton = UIButton(type: .system)
    private let micButton = UIButton(type: .system)
    private let recordButton = UIButton(type: .system)
    private let sendButton = UIButton(type: .system)
    
    // For naive in-app replayKit capturing (only inside app!)
    private var isRecording = false
    private var blinkTimer: Timer?
    private var frameCaptureTimer: Timer?
    
    // Array of images from library or partial in-app capture
    private var userImages: [UIImage] = []
    
    // For the small preview in the input bar
    private let selectedImagePreview = UIImageView()
    private let removeImageButton = UIButton(type: .system)
    private var previewContainer: UIStackView!
    
    // Constraints
    private var inputContainerBottomConstraint: NSLayoutConstraint!
    private var inputTextViewHeightConstraint: NSLayoutConstraint!
    
    // The chat messages array
    private var messages: [ChatMessage] = []
    
    // GPT-4 Key
    private let openAIKey = "abc"
    
    // Limit text input lines
    private let maxNumberOfLines: CGFloat = 6
    
    /// For real outside-app capturing, we rely on the Broadcast Extension (outside this code).
    /// We'll read frames from the shared container when user taps "Send."
    private let appGroupID = "group.com.techpal.mobile.ChatGPTScreenRecorder"
    private let framesFolder = "BroadcastFrames"
    
    /// We limit total images per request to 10
    private let maxImagesPerRequest = 10
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        
        // Force nav bar white
        navigationController?.navigationBar.isTranslucent = false
        let appearance = UINavigationBarAppearance()
        appearance.backgroundColor = .white
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        
        // If you have a navLogo in assets:
        let logoImageView = UIImageView(image: UIImage(named: "navLogo"))
        logoImageView.contentMode = .scaleAspectFit
        navigationItem.titleView = logoImageView
        
        setupTableView()
        setupInputContainer()
        setupKeyboardObservers()
        
        // recordButton default color
        recordButton.tintColor = .blue
    }
    
    // MARK: - Table Setup
    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .white
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.estimatedRowHeight = 44
        tableView.rowHeight = UITableView.automaticDimension
        
        tableView.register(ChatMessageCell.self, forCellReuseIdentifier: ChatMessageCell.identifier)
        
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    // MARK: - Input Container
    private func setupInputContainer() {
        inputContainer.backgroundColor = UIColor(white: 0.95, alpha: 1)
        inputContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(inputContainer)
        
        NSLayoutConstraint.activate([
            inputContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
        inputContainerBottomConstraint =
            inputContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        inputContainerBottomConstraint.isActive = true
        
        let vStack = UIStackView()
        vStack.axis = .vertical
        vStack.alignment = .fill
        vStack.distribution = .fill
        vStack.spacing = 6
        vStack.translatesAutoresizingMaskIntoConstraints = false
        inputContainer.addSubview(vStack)
        
        NSLayoutConstraint.activate([
            vStack.topAnchor.constraint(equalTo: inputContainer.topAnchor, constant: 6),
            vStack.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 6),
            vStack.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -6),
            vStack.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor, constant: -6)
        ])
        
        // Multi-line text view
        inputTextView.font = UIFont.systemFont(ofSize: 16)
        inputTextView.isScrollEnabled = false
        inputTextView.layer.cornerRadius = 6
        inputTextView.layer.borderWidth = 1
        inputTextView.layer.borderColor = UIColor.lightGray.cgColor
        inputTextView.delegate = self
        inputTextView.translatesAutoresizingMaskIntoConstraints = false
        
        let oneLineHeight = inputTextView.font?.lineHeight ?? 20
        inputTextViewHeightConstraint =
            inputTextView.heightAnchor.constraint(equalToConstant: oneLineHeight + 16)
        inputTextViewHeightConstraint.isActive = true
        
        // Horizontal row for buttons & preview
        buttonsContainer.axis = .horizontal
        buttonsContainer.alignment = .center
        buttonsContainer.distribution = .equalSpacing
        buttonsContainer.translatesAutoresizingMaskIntoConstraints = false
        
        // A small preview stack
        previewContainer = UIStackView()
        previewContainer.axis = .horizontal
        previewContainer.alignment = .center
        previewContainer.spacing = 4
        previewContainer.isHidden = true
        
        selectedImagePreview.contentMode = .scaleAspectFill
        selectedImagePreview.clipsToBounds = true
        selectedImagePreview.widthAnchor.constraint(equalToConstant: 50).isActive = true
        selectedImagePreview.heightAnchor.constraint(equalToConstant: 50).isActive = true
        
        removeImageButton.setTitle("X", for: .normal)
        removeImageButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 14)
        removeImageButton.addTarget(self,
                                    action: #selector(removeImageButtonTapped),
                                    for: .touchUpInside)
        
        previewContainer.addArrangedSubview(selectedImagePreview)
        previewContainer.addArrangedSubview(removeImageButton)
        
        // Buttons
        uploadImageButton.setImage(UIImage(systemName: "photo"), for: .normal)
        uploadImageButton.tintColor = .black
        uploadImageButton.addTarget(self,
                                    action: #selector(uploadImageButtonTapped),
                                    for: .touchUpInside)
        
        micButton.setImage(UIImage(systemName: "mic"), for: .normal)
        micButton.tintColor = .black
        micButton.addTarget(self,
                            action: #selector(micButtonTapped),
                            for: .touchUpInside)
        
        recordButton.setImage(UIImage(systemName: "circle.circle"), for: .normal)
        recordButton.addTarget(self,
                               action: #selector(recordButtonTapped),
                               for: .touchUpInside)
        
        sendButton.setImage(UIImage(systemName: "paperplane.fill"), for: .normal)
        sendButton.tintColor = .black
        sendButton.addTarget(self,
                             action: #selector(sendButtonTapped),
                             for: .touchUpInside)
        
        // Add them
        buttonsContainer.addArrangedSubview(previewContainer)
        buttonsContainer.addArrangedSubview(uploadImageButton)
        buttonsContainer.addArrangedSubview(micButton)
        buttonsContainer.addArrangedSubview(recordButton)
        buttonsContainer.addArrangedSubview(sendButton)
        
        vStack.addArrangedSubview(inputTextView)
        vStack.addArrangedSubview(buttonsContainer)
    }
    
    // MARK: - Keyboard
    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleKeyboardWillShow(_:)),
                                               name: UIResponder.keyboardWillShowNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleKeyboardWillHide(_:)),
                                               name: UIResponder.keyboardWillHideNotification,
                                               object: nil)
    }
    
    @objc private func handleKeyboardWillShow(_ note: Notification) {
        guard let kbFrame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
        else { return }
        
        let kbHeight = kbFrame.height - view.safeAreaInsets.bottom
        
        UIView.animate(withDuration: 0.3) {
            self.inputContainerBottomConstraint.constant = -kbHeight
            self.view.layoutIfNeeded()
            self.scrollSoOnlyNewMessageVisible()
        }
    }
    
    @objc private func handleKeyboardWillHide(_ note: Notification) {
        UIView.animate(withDuration: 0.3) {
            self.inputContainerBottomConstraint.constant = 0
            self.view.layoutIfNeeded()
            self.scrollSoOnlyNewMessageVisible()
        }
    }
    
    private func scrollSoOnlyNewMessageVisible() {
        guard !messages.isEmpty else { return }
        let lastIndex = IndexPath(row: messages.count - 1, section: 0)
        tableView.scrollToRow(at: lastIndex, at: .top, animated: true)
    }
    
    // MARK: - Buttons
    @objc private func removeImageButtonTapped() {
        userImages.removeAll()
        selectedImagePreview.image = nil
        previewContainer.isHidden = true
    }
    
    @objc private func uploadImageButtonTapped() {
        inputTextView.resignFirstResponder()
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = self
        present(picker, animated: true)
    }
    
    @objc private func micButtonTapped() {
        inputTextView.resignFirstResponder()
        print("Mic tapped (placeholder).")
    }
    
    // MARK: - Broadcasting Outside the App
    // We'll show the user a broadcast activity picker, but we won't parse frames in-app:
    // The extension writes frames to the shared container, we load them when user taps "Send."
    // => Real "outside-app" capturing requires that extension (SampleHandler.swift).
    
    @objc private func recordButtonTapped() {
        // For clarity, we only do in-app naive capture with startCapture,
        // but to record outside the app, we must do broadcast extension.
        // We'll just call "showBroadcastPicker()" for the system flow:
        showBroadcastPicker()
    }
    
    private func showBroadcastPicker() {
        RPBroadcastActivityViewController.load { activityVC, error in
            if let avc = activityVC {
                avc.delegate = self
                self.present(avc, animated: true)
            } else if let e = error {
                print("Error loading BroadcastActivityVC: \(e)")
            }
        }
    }
    
    // MARK: - Indefinite in-app capture snippet (not used for outside app)
    // We keep it here for reference, but to truly capture outside the app, we rely on broadcast extension.
    private func startInAppCapture() {
        guard !RPScreenRecorder.shared().isRecording else { return }
        RPScreenRecorder.shared().startCapture { [weak self] buffer, _, err in
            // 1fps approach if you want
        } completionHandler: { error in
            // handle
        }
    }
    private func stopInAppCapture() {
        // ...
    }
    
    // MARK: - "Send" => Combine typed text + library images + up to 10 frames from broadcast
    @objc private func sendButtonTapped() {
        // 1) If we are in naive in-app capture, stop it. (If used)
        // 2) Grab typed text
        let userText = inputTextView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 3) Load frames from broadcast extension container
        let broadcastImages = loadFramesFromSharedContainer()
        
        // 4) Combine them with any images the user picked from library
        var finalImages: [UIImage] = []
        finalImages.append(contentsOf: userImages)
        finalImages.append(contentsOf: broadcastImages)
        
        // Cap at 10
        if finalImages.count > maxImagesPerRequest {
            finalImages = Array(finalImages.prefix(maxImagesPerRequest))
        }
        
        // If no text & no images => do nothing
        guard !(userText.isEmpty && finalImages.isEmpty) else { return }
        
        // Clear text input
        inputTextView.text = ""
        inputTextView.resignFirstResponder()
        textViewDidChange(inputTextView)
        
        // Clear local images
        userImages.removeAll()
        removeImageButtonTapped() // hides preview
        
        // Also clear the frames in the container now that we've "used" them
        clearFramesInSharedContainer()
        
        // 5) Add user message
        let userMsg = ChatMessage(sender: .user, kind: .combined(text: userText.isEmpty ? nil : userText,
                                                                images: finalImages))
        messages.append(userMsg)
        tableView.reloadData()
        scrollSoOnlyNewMessageVisible()
        
        // 6) Show bot "typing"
        let typingMsg = ChatMessage(sender: .bot, kind: .typingIndicator)
        messages.append(typingMsg)
        tableView.reloadData()
        
        // 7) Build conversation for GPT
        let payload = buildConversationPayload()
        
        // 8) Send to GPT
        fetchChatGPTResponse(conversationPayload: payload) { [weak self] botReply in
            DispatchQueue.main.async {
                // remove typing
                if let last = self?.messages.last, case .typingIndicator = last.kind {
                    self?.messages.removeLast()
                }
                // create bot msg
                let botMsg = ChatMessage(sender: .bot,
                                         kind: .combined(text: botReply, images: []))
                self?.messages.append(botMsg)
                self?.tableView.reloadData()
                self?.scrollSoOnlyNewMessageVisible()
            }
        }
    }
    
    // MARK: - Helpers for Reading/Wiping Container
    
    /// Loads frames from broadcast extension shared container, up to 10
    private func loadFramesFromSharedContainer() -> [UIImage] {
        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else {
            return []
        }
        let framesPath = containerURL.appendingPathComponent(framesFolder, isDirectory: true)
        
        guard let files = try? FileManager.default.contentsOfDirectory(at: framesPath,
                                                                       includingPropertiesForKeys: nil,
                                                                       options: [])
        else { return [] }
        
        let pngs = files.filter { $0.pathExtension.lowercased() == "png" }
                        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        
        var images: [UIImage] = []
        for fURL in pngs {
            if let data = try? Data(contentsOf: fURL),
               let img = UIImage(data: data) {
                images.append(img)
            }
        }
        
        // The caller will cap them to 10 total, but let's just return them all
        return images
    }
    
    private func clearFramesInSharedContainer() {
        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else { return }
        
        let framesPath = containerURL.appendingPathComponent(framesFolder, isDirectory: true)
        try? FileManager.default.removeItem(at: framesPath)
    }
    
    // MARK: - GPT-4 Chat
    private func buildConversationPayload() -> [[String: Any]] {
        // Convert each ChatMessage to the expected array for GPT
        var arr: [[String: Any]] = []
        for m in messages {
            if case .typingIndicator = m.kind {
                continue
            }
            switch m.kind {
            case .combined(let text, let images):
                var contentArray: [[String: Any]] = []
                if let t = text, !t.isEmpty {
                    contentArray.append(["type": "text", "text": t])
                }
                for img in images {
                    if let pngData = img.pngData() {
                        let b64 = pngData.base64EncodedString()
                        contentArray.append([
                            "type": "image_url",
                            "image_url": ["url": "data:image/png;base64,\(b64)"]
                        ])
                    }
                }
                let role = (m.sender == .user) ? "user" : "assistant"
                arr.append([
                    "role": role,
                    "content": contentArray
                ])
                
            case .typingIndicator:
                // skip
                break
            }
        }
        return arr
    }
    
    private func fetchChatGPTResponse(conversationPayload: [[String: Any]],
                                      completion: @escaping (String) -> Void) {
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            completion("Invalid URL.")
            return
        }
        
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // We specify "model": "gpt-4o" or another vision-capable model
        let body: [String: Any] = [
            "model": "gpt-4o", // or "gpt-4o-mini", etc.
            "messages": conversationPayload,
            "max_tokens": 300
        ]
        
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion("Error encoding request body: \(error.localizedDescription)")
            return
        }
        
        URLSession.shared.dataTask(with: req) { data, _, error in
            if let e = error {
                completion("Network error: \(e.localizedDescription)")
                return
            }
            guard let data = data else {
                completion("No data from server.")
                return
            }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let first = choices.first,
                   let message = first["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    
                    completion(content.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    completion("Unable to parse GPT response.")
                }
            } catch {
                completion("JSON parse error: \(error.localizedDescription)")
            }
        }.resume()
    }
}
// MARK: - UITableViewDataSource & UITableViewDelegate
extension ChatViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView,
                   numberOfRowsInSection section: Int) -> Int {
        return messages.count
    }
    
    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        guard let cell = tableView.dequeueReusableCell(withIdentifier: ChatMessageCell.identifier,
                                                       for: indexPath) as? ChatMessageCell
        else {
            return UITableViewCell()
        }
        
        let msg = messages[indexPath.row]
        cell.configure(with: msg)
        return cell
    }
}
// MARK: - UIImagePickerControllerDelegate (for library images)
extension ChatViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        
        picker.dismiss(animated: true)
        
        if let picked = info[.originalImage] as? UIImage {
            // just store 1 for now
            userImages.removeAll()
            userImages.append(picked)
            selectedImagePreview.image = picked
            previewContainer.isHidden = false
        }
    }
}
// MARK: - UITextViewDelegate (auto-growing text)
extension ChatViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        let size = CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)
        let fittingSize = textView.sizeThatFits(size)
        
        let oneLineHeight = textView.font?.lineHeight ?? 20
        let maxHeight = oneLineHeight * maxNumberOfLines + 16
        
        let newHeight = min(fittingSize.height, maxHeight)
        inputTextViewHeightConstraint.constant = newHeight
        
        UIView.animate(withDuration: 0.1) {
            self.view.layoutIfNeeded()
        }
    }
}
// MARK: - RPBroadcastActivityViewControllerDelegate
extension ChatViewController: RPBroadcastActivityViewControllerDelegate {
    func broadcastActivityViewController(_ broadcastActivityViewController: RPBroadcastActivityViewController,
                                         didFinishWith broadcastController: RPBroadcastController?,
                                         error: Error?) {
        guard error == nil else {
            print("User canceled or error: \(error!)")
            broadcastActivityViewController.dismiss(animated: true)
            return
        }
        
        broadcastActivityViewController.dismiss(animated: true) {
            broadcastController?.startBroadcast { err in
                if let e = err {
                    print("Error startBroadcast: \(e)")
                } else {
                    print("Broadcast started!")
                }
            }
        }
    }
}

