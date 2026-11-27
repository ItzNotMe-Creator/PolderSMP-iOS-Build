import UIKit
import WebKit
import LocalAuthentication
import Security
import AVFoundation

@main class App: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private let panel = Panel()
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = panel
        window?.makeKeyAndVisible()
        return true
    }
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        panel.pair(url)
    }
    func applicationDidEnterBackground(_ application: UIApplication) {
        panel.lockForReturn()
    }
    func applicationWillEnterForeground(_ application: UIApplication) {
        panel.reopenLogin()
    }
    func applicationDidBecomeActive(_ application: UIApplication) { panel.beginFaceIfNeeded() }
}


/* Optional local camera preview. Apple Face ID and Keychain perform the actual security check. */
final class GuidedCameraRing: UIView {
    let preview = AVCaptureVideoPreviewLayer()
    private let disk = CALayer()
    private var marks = [CAShapeLayer]()
    private let highlight = CAShapeLayer()
    override init(frame:CGRect){
        super.init(frame:frame)
        isAccessibilityElement=false
        disk.backgroundColor=UIColor.secondarySystemBackground.cgColor
        disk.masksToBounds=true
        preview.videoGravity = .resizeAspectFill
        disk.addSublayer(preview);layer.addSublayer(disk)
        for _ in 0..<64 {
            let mark=CAShapeLayer();mark.lineWidth=2.6;mark.lineCap = .round
            mark.strokeColor=UIColor.tertiaryLabel.cgColor;layer.addSublayer(mark);marks.append(mark)
        }
        highlight.fillColor=UIColor.clear.cgColor
        highlight.strokeColor=UIColor.systemBlue.withAlphaComponent(0.45).cgColor
        highlight.lineWidth=1;layer.addSublayer(highlight)
    }
    required init?(coder:NSCoder){fatalError("init(coder:)")}
    override func layoutSubviews(){
        super.layoutSubviews()
        let d=min(bounds.width,bounds.height), c=CGPoint(x:bounds.midX,y:bounds.midY)
        let diameter=max(0,d-45), inner=max(0,d/2-13),outer=max(0,d/2-3)
        CATransaction.begin();CATransaction.setDisableActions(true)
        disk.frame=CGRect(x:c.x-diameter/2,y:c.y-diameter/2,width:diameter,height:diameter)
        disk.cornerRadius=diameter/2;preview.frame=disk.bounds
        for (i,m) in marks.enumerated(){
            let a=CGFloat(i)*2*CGFloat.pi/64-CGFloat.pi/8
            let p=UIBezierPath();p.move(to:CGPoint(x:c.x+cos(a)*inner,y:c.y+sin(a)*inner))
            p.addLine(to:CGPoint(x:c.x+cos(a)*outer,y:c.y+sin(a)*outer));m.path=p.cgPath
        }
        highlight.path=UIBezierPath(ovalIn:disk.frame.insetBy(dx:-3,dy:-3)).cgPath
        CATransaction.commit()
    }
    func update(sectors:Set<Int>){
        for (i,m) in marks.enumerated(){
            // Decorative camera readiness, never an identity result.
            let color=sectors.contains(i/8) ? UIColor.systemBlue.cgColor : UIColor.tertiaryLabel.cgColor
            guard m.strokeColor != color else{continue}
            let previous=m.presentation()?.strokeColor ?? m.strokeColor
            CATransaction.begin();CATransaction.setDisableActions(true);m.strokeColor=color;CATransaction.commit()
            if !UIAccessibility.isReduceMotionEnabled {
                let a=CABasicAnimation(keyPath:"strokeColor");a.fromValue=previous;a.toValue=color;a.duration=0.34
                a.timingFunction=CAMediaTimingFunction(name:.easeInEaseOut)
                m.add(a,forKey:"color")
            }
        }
    }
}

final class FaceGuideController:UIViewController {
    private let session=AVCaptureSession()
    private let cameraQueue=DispatchQueue(label:"nl.poldersmp.camera")
    private let ring=GuidedCameraRing(frame:.zero)
    private let heading=UILabel(), detail=UILabel(), progress=UILabel()
    private let action=UIButton(type:.system)
    private let roundProgress=UIProgressView(progressViewStyle:.default)
    private let privacy=UILabel()
    private var active=false
    private var configured=false // cameraQueue only
    private var completion: ((Bool)->Void)?
    init(completion:@escaping (Bool)->Void){
        self.completion=completion;super.init(nibName:nil,bundle:nil)
        modalPresentationStyle = .fullScreen
    }
    required init?(coder:NSCoder){fatalError("init(coder:)")}
    override func viewDidLoad(){
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let cancel=UIButton(type:.system);cancel.setTitle("Annuleren",for:.normal)
        cancel.addTarget(self,action:#selector(cancelGuide),for:.touchUpInside)
        cancel.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(cancel)
        let scroll=UIScrollView();scroll.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(scroll)
        let brand=UILabel();brand.text="POLDERSMP  /  FACE ID";brand.font = .systemFont(ofSize:11,weight:.semibold)
        brand.textColor = .secondaryLabel
        for label in [heading,detail,progress,privacy] {label.numberOfLines=0;label.textAlignment = .center;label.adjustsFontForContentSizeCategory=true}
        heading.font = .preferredFont(forTextStyle:.largeTitle);heading.text="Configureer Face ID"
        detail.font = .preferredFont(forTextStyle:.body);detail.textColor = .secondaryLabel
        detail.text="Kijk gewoon naar je iPhone. Je hoeft je hoofd niet te draaien."
        progress.font = .monospacedDigitSystemFont(ofSize:14,weight:.medium);progress.text="Klaar om te bevestigen"
        privacy.font = .preferredFont(forTextStyle:.caption1);privacy.textColor = .secondaryLabel
        privacy.text="De camera is optioneel. Apple controleert je gezicht. PolderSMP slaat geen foto’s op."
        roundProgress.progressTintColor = .systemBlue
        roundProgress.isHidden=true
        var cfg=UIButton.Configuration.filled();cfg.title="Face ID inschakelen";cfg.image=UIImage(systemName:"faceid");cfg.imagePadding=10;cfg.cornerStyle = .large
        action.configuration=cfg;action.addTarget(self,action:#selector(continueGuide),for:.touchUpInside)
        ring.translatesAutoresizingMaskIntoConstraints=false
        let stack=UIStackView(arrangedSubviews:[brand,heading,detail,ring,progress,roundProgress,action,privacy])
        stack.axis = .vertical;stack.alignment = .center;stack.spacing=14
        stack.setCustomSpacing(20,after:detail);stack.setCustomSpacing(20,after:roundProgress)
        stack.translatesAutoresizingMaskIntoConstraints=false;scroll.addSubview(stack)
        let width=ring.widthAnchor.constraint(equalToConstant:286);width.priority = .defaultHigh
        let centered=stack.centerYAnchor.constraint(equalTo:scroll.contentLayoutGuide.centerYAnchor);centered.priority = .defaultHigh
        let full=scroll.contentLayoutGuide.heightAnchor.constraint(equalTo:scroll.frameLayoutGuide.heightAnchor);full.priority = .defaultLow
        NSLayoutConstraint.activate([
            cancel.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor,constant:6),
            cancel.leadingAnchor.constraint(equalTo:view.safeAreaLayoutGuide.leadingAnchor,constant:20),
            cancel.heightAnchor.constraint(greaterThanOrEqualToConstant:44),
            scroll.topAnchor.constraint(equalTo:cancel.bottomAnchor,constant:4),scroll.bottomAnchor.constraint(equalTo:view.safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo:view.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:view.trailingAnchor),
            scroll.contentLayoutGuide.widthAnchor.constraint(equalTo:scroll.frameLayoutGuide.widthAnchor),full,centered,
            stack.centerXAnchor.constraint(equalTo:scroll.contentLayoutGuide.centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo:scroll.contentLayoutGuide.leadingAnchor,constant:22),
            stack.trailingAnchor.constraint(lessThanOrEqualTo:scroll.contentLayoutGuide.trailingAnchor,constant:-22),
            stack.topAnchor.constraint(greaterThanOrEqualTo:scroll.contentLayoutGuide.topAnchor,constant:12),
            stack.bottomAnchor.constraint(lessThanOrEqualTo:scroll.contentLayoutGuide.bottomAnchor,constant:-20),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant:420),
            ring.widthAnchor.constraint(lessThanOrEqualTo:stack.widthAnchor),width,
            ring.heightAnchor.constraint(equalTo:ring.widthAnchor),
            roundProgress.widthAnchor.constraint(equalToConstant:120),
            action.widthAnchor.constraint(equalTo:stack.widthAnchor),action.heightAnchor.constraint(greaterThanOrEqualToConstant:50)
        ])
        ring.preview.session=session
    }
    override func viewDidAppear(_ animated:Bool){super.viewDidAppear(animated);active=true;requestCamera()}
    override func viewWillDisappear(_ animated:Bool){super.viewWillDisappear(animated);active=false;stopCamera()}
    private func requestCamera(){
        switch AVCaptureDevice.authorizationStatus(for:.video){
        case .authorized: startCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for:.video){[weak self] allowed in DispatchQueue.main.async{
                guard let self=self,self.active else{return}
                if allowed {self.startCamera()}else{self.cameraUnavailable()}
            }}
        default:cameraUnavailable()
        }
    }
    private func cameraUnavailable(){
        guard active else{return}
        detail.text="Je kunt ook zonder cameraweergave doorgaan. Apple controleert je gezicht."
        progress.text="Camera optioneel"
    }
    private func startCamera(){
        cameraQueue.async{[weak self] in
            guard let self=self else{return}
            if !self.configured {
                guard let camera=AVCaptureDevice.default(.builtInWideAngleCamera,for:.video,position:.front),
                      let input=try? AVCaptureDeviceInput(device:camera) else{
                    DispatchQueue.main.async{self.cameraUnavailable()};return
                }
                self.session.beginConfiguration()
                self.session.sessionPreset = .medium
                guard self.session.canAddInput(input) else{
                    self.session.commitConfiguration();DispatchQueue.main.async{self.cameraUnavailable()};return
                }
                self.session.addInput(input)
                self.session.commitConfiguration();self.configured=true
            }
            DispatchQueue.main.async{
                if let connection=self.ring.preview.connection{
                    if connection.isVideoOrientationSupported {connection.videoOrientation = .portrait}
                    if connection.isVideoMirroringSupported {connection.automaticallyAdjustsVideoMirroring=false;connection.isVideoMirrored=true}
                }
            }
            if !self.session.isRunning {self.session.startRunning()}
            DispatchQueue.main.async{[weak self] in self?.cameraReady()}
        }
    }
    private func stopCamera(completion: (() -> Void)? = nil){
        cameraQueue.async{[session] in
            if session.isRunning {session.stopRunning()}
            if let completion=completion {DispatchQueue.main.async{completion()}}
        }
    }
    private func cameraReady(){
        guard active,completion != nil else{return}
        progress.text="Cameraweergave gereed"
        // Decorative readiness indicator, not a biometric or identity check.
        for step in 1...8 {
            let delay=UIAccessibility.isReduceMotionEnabled ? 0 : Double(step)*0.065
            DispatchQueue.main.asyncAfter(deadline:.now()+delay){[weak self] in
                guard let self=self,self.active,self.completion != nil else{return}
                self.ring.update(sectors:Set(0..<step))
            }
        }
    }
    @objc private func cancelGuide(){finish(false)}
    @objc private func continueGuide(){finish(true)}
    private func finish(_ confirmed:Bool){
        guard let callback=completion else{return}
        completion=nil;active=false
        action.isEnabled=false
        stopCamera{[weak self] in
            guard let self=self else{callback(false);return}
            self.dismiss(animated:!UIAccessibility.isReduceMotionEnabled){callback(confirmed)}
        }
    }
}


final class IslandAuthView: UIView {
    private let shell=UIView(), glyph=UIImageView(), title=UILabel(), subtitle=UILabel()
    private let orbit=CAShapeLayer()
    private var w:NSLayoutConstraint!, h:NSLayoutConstraint!
    override init(frame:CGRect){
        super.init(frame:frame)
        isUserInteractionEnabled=false
        shell.backgroundColor = .black; shell.layer.cornerRadius=28
        shell.layer.cornerCurve = .continuous; shell.clipsToBounds=true
        shell.translatesAutoresizingMaskIntoConstraints=false;addSubview(shell)
        w=shell.widthAnchor.constraint(equalToConstant:126);h=shell.heightAnchor.constraint(equalToConstant:36)
        let icon=UIView();icon.translatesAutoresizingMaskIntoConstraints=false
        glyph.contentMode = .scaleAspectFit;glyph.translatesAutoresizingMaskIntoConstraints=false
        icon.addSubview(glyph);orbit.fillColor=UIColor.clear.cgColor;orbit.lineWidth=2;orbit.lineCap = .round
        orbit.path=UIBezierPath(ovalIn:CGRect(x:2,y:2,width:44,height:44)).cgPath
        orbit.frame=CGRect(x:0,y:0,width:48,height:48);icon.layer.addSublayer(orbit)
        title.font = .systemFont(ofSize:16,weight:.semibold);title.textColor = .white
        subtitle.font = .systemFont(ofSize:12,weight:.medium);subtitle.textColor = .lightGray
        let text=UIStackView(arrangedSubviews:[title,subtitle]);text.axis = .vertical;text.spacing=4
        let row=UIStackView(arrangedSubviews:[icon,text]);row.alignment = .center;row.spacing=14
        row.translatesAutoresizingMaskIntoConstraints=false;shell.addSubview(row)
        NSLayoutConstraint.activate([w,h,shell.topAnchor.constraint(equalTo:topAnchor),shell.centerXAnchor.constraint(equalTo:centerXAnchor),shell.bottomAnchor.constraint(equalTo:bottomAnchor),
            icon.widthAnchor.constraint(equalToConstant:48),icon.heightAnchor.constraint(equalToConstant:48),
            glyph.centerXAnchor.constraint(equalTo:icon.centerXAnchor),glyph.centerYAnchor.constraint(equalTo:icon.centerYAnchor),glyph.widthAnchor.constraint(equalToConstant:27),glyph.heightAnchor.constraint(equalToConstant:27),
            row.leadingAnchor.constraint(equalTo:shell.leadingAnchor,constant:16),row.topAnchor.constraint(equalTo:shell.topAnchor,constant:13)])
        alpha=0
    }
    required init?(coder:NSCoder){fatalError("init(coder:)")}
    func show(_ state:FaceLockView.State,attempt:Int){
        orbit.removeAllAnimations()
        let tint:UIColor
        switch state {
        case .waiting,.scanning:
            tint=UIColor(red:0.46,green:0.73,blue:1,alpha:1);title.text="Face ID";subtitle.text=state == .waiting ? "Veilige verbinding" : "Poging \(attempt) van 3";glyph.image=UIImage(systemName:"faceid")
        case .failure:
            tint = .systemRed;title.text="Niet herkend";subtitle.text="\(max(0,3-attempt)) pogingen over";glyph.image=UIImage(systemName:"faceid")
        case .success:
            tint = .systemGreen;title.text="Ontgrendeld";subtitle.text="Welkom bij PolderSMP";glyph.image=UIImage(systemName:"checkmark")
        }
        glyph.tintColor=tint;orbit.strokeColor=tint.cgColor;orbit.strokeEnd=state == .scanning ? 0.26:1
        w.constant=286;h.constant=76
        let change={self.alpha=1;self.superview?.layoutIfNeeded()}
        if UIAccessibility.isReduceMotionEnabled {change()}else{UIView.animate(withDuration:0.65,delay:0,usingSpringWithDamping:0.86,initialSpringVelocity:0.1,options:[.beginFromCurrentState,.allowUserInteraction],animations:change)}
        if state == .scanning && !UIAccessibility.isReduceMotionEnabled{
            let spin=CABasicAnimation(keyPath:"transform.rotation.z");spin.fromValue=0;spin.toValue=Double.pi*2;spin.duration=1.6;spin.repeatCount = .infinity;orbit.add(spin,forKey:"spin")
        }
    }
    func reset(){orbit.removeAllAnimations();layer.removeAllAnimations();shell.layer.removeAllAnimations();alpha=0;w.constant=126;h.constant=36}
}

final class FaceLockView: UIView {
    enum State { case waiting, scanning, failure, success }
    private let islandAuth=IslandAuthView(frame:.zero)
    private let heading = UILabel()
    private let detail = UILabel()
    private let count = UILabel()
    private let glyph = UIImageView()
    private let ring = UIView()
    private let scan = UIView()
    private let orbit = CAShapeLayer()
    private let orbitMask = CAShapeLayer()
    private let code = UIButton(type: .system)
    var useCode: (() -> Void)?
    private(set) var state: State = .waiting

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        accessibilityViewIsModal = true
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        islandAuth.translatesAutoresizingMaskIntoConstraints=false;addSubview(islandAuth)
        NSLayoutConstraint.activate([islandAuth.topAnchor.constraint(equalTo:safeAreaLayoutGuide.topAnchor,constant:5),islandAuth.centerXAnchor.constraint(equalTo:centerXAnchor),islandAuth.widthAnchor.constraint(equalTo:widthAnchor)])
        let brand = UILabel()
        brand.text = "P O L D E R S M P  /  A T L A S"
        brand.font = .systemFont(ofSize: 11, weight: .semibold)
        brand.textColor = .secondaryLabel
        brand.textAlignment = .center
        brand.adjustsFontSizeToFitWidth = true
        ring.translatesAutoresizingMaskIntoConstraints = false
        ring.layer.cornerRadius = 76
        ring.layer.borderWidth = 0
        orbit.fillColor=UIColor.clear.cgColor;orbit.lineWidth=2.2;orbit.lineCap = .round
        orbitMask.fillColor=UIColor.clear.cgColor;orbitMask.strokeColor=UIColor.white.cgColor;orbitMask.lineWidth=3
        orbit.mask=orbitMask;ring.layer.addSublayer(orbit)
        glyph.translatesAutoresizingMaskIntoConstraints = false
        glyph.contentMode = .scaleAspectFit
        glyph.preferredSymbolConfiguration = .init(pointSize: 54, weight: .light)
        ring.addSubview(glyph)
        scan.translatesAutoresizingMaskIntoConstraints = false
        scan.layer.cornerRadius = 1
        ring.addSubview(scan)
        NSLayoutConstraint.activate([
            ring.widthAnchor.constraint(equalToConstant: 152),ring.heightAnchor.constraint(equalToConstant: 152),
            glyph.centerXAnchor.constraint(equalTo: ring.centerXAnchor),glyph.centerYAnchor.constraint(equalTo: ring.centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: 65),glyph.heightAnchor.constraint(equalToConstant: 65),
            scan.widthAnchor.constraint(equalToConstant: 74),scan.heightAnchor.constraint(equalToConstant: 2),
            scan.centerXAnchor.constraint(equalTo: ring.centerXAnchor),scan.centerYAnchor.constraint(equalTo: ring.centerYAnchor)
        ])
        heading.font = .preferredFont(forTextStyle: .title1)
        heading.textColor = .label
        heading.adjustsFontForContentSizeCategory = true
        heading.textAlignment = .center
        heading.numberOfLines = 0
        detail.font = .preferredFont(forTextStyle: .body)
        detail.textColor = .secondaryLabel
        detail.numberOfLines = 0
        detail.textAlignment = .center
        count.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        count.textColor = .secondaryLabel
        count.textAlignment = .center
        count.numberOfLines = 0
        var cfg = UIButton.Configuration.tinted()
        cfg.title = "Gebruik toegangscode"
        cfg.image = UIImage(systemName: "number")
        cfg.imagePadding = 8
        cfg.cornerStyle = .large
        code.configuration = cfg
        code.addTarget(self, action: #selector(codeTapped), for: .touchUpInside)
        let lock = UILabel()
        lock.text = "Beveiligd met Apple Face ID"
        lock.textAlignment = .center
        lock.font = .preferredFont(forTextStyle: .caption1)
        lock.textColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews:[brand,ring,heading,detail,count,code,lock])
        stack.axis = .vertical;stack.alignment = .center;stack.spacing = 16
        stack.setCustomSpacing(32,after:brand);stack.setCustomSpacing(28,after:ring)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        let center = stack.centerYAnchor.constraint(equalTo: scroll.contentLayoutGuide.centerYAnchor)
        center.priority = .defaultHigh
        let fit = scroll.contentLayoutGuide.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        fit.priority = .defaultLow
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo:islandAuth.bottomAnchor,constant:8),
            scroll.bottomAnchor.constraint(equalTo:safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo:leadingAnchor),scroll.trailingAnchor.constraint(equalTo:trailingAnchor),
            scroll.contentLayoutGuide.widthAnchor.constraint(equalTo:scroll.frameLayoutGuide.widthAnchor),
            fit,center,stack.centerXAnchor.constraint(equalTo:scroll.contentLayoutGuide.centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo:scroll.contentLayoutGuide.leadingAnchor,constant:24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo:scroll.contentLayoutGuide.trailingAnchor,constant:-24),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant:420),
            stack.topAnchor.constraint(greaterThanOrEqualTo:scroll.contentLayoutGuide.topAnchor,constant:24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo:scroll.contentLayoutGuide.bottomAnchor,constant:-24),
            code.widthAnchor.constraint(equalTo:stack.widthAnchor),
            code.heightAnchor.constraint(greaterThanOrEqualToConstant:50)
        ])
        apply(.waiting,attempt:0)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func codeTapped(){ UISelectionFeedbackGenerator().selectionChanged();useCode?() }

    override func layoutSubviews(){
        super.layoutSubviews()
        let center=CGPoint(x:ring.bounds.midX,y:ring.bounds.midY), radius=max(0,ring.bounds.width/2-3)
        let p=UIBezierPath()
        for i in 0..<48{let a=CGFloat(i)*2*CGFloat.pi/48; p.move(to:CGPoint(x:center.x+cos(a)*(radius-5),y:center.y+sin(a)*(radius-5)));p.addLine(to:CGPoint(x:center.x+cos(a)*radius,y:center.y+sin(a)*radius))}
        CATransaction.begin();CATransaction.setDisableActions(true)
        orbit.frame=ring.bounds;orbit.path=p.cgPath;orbitMask.frame=ring.bounds
        orbitMask.path=UIBezierPath(ovalIn:ring.bounds.insetBy(dx:5.5,dy:5.5)).cgPath
        orbitMask.lineWidth=9;CATransaction.commit()
    }
    func apply(_ next:State,attempt:Int) {
        state=next
        ring.alpha=1
        islandAuth.show(next,attempt:attempt)
        ring.layer.removeAllAnimations()
        scan.layer.removeAllAnimations();orbitMask.removeAllAnimations()
        let tint:UIColor
        let symbol:String
        switch next {
        case .waiting:
            tint = .systemBlue;symbol="faceid";heading.text="Welkom terug"
            detail.text="We maken je veilige aanmelding gereed."
            count.text="Face ID";code.isEnabled=true
        case .scanning:
            tint = .systemBlue;symbol="faceid";heading.text="Face ID"
            detail.text="Kijk naar je iPhone om te ontgrendelen."
            count.text="Poging \(attempt) van 3";code.isEnabled=true
        case .failure:
            tint = .systemRed;symbol="faceid";heading.text="Niet herkend"
            detail.text="Probeer opnieuw of gebruik je toegangscode."
            count.text=attempt<3 ? "\(3-attempt) pogingen over" : "Gebruik je toegangscode"
            code.isEnabled=true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .success:
            tint = .systemGreen;symbol="checkmark";heading.text="Ontgrendeld"
            detail.text="Je veilige sessie is gereed."
            count.text="Welkom bij PolderSMP";code.isEnabled=false
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        glyph.image=UIImage(systemName:symbol);glyph.tintColor=tint
        ring.backgroundColor=tint.withAlphaComponent(0.07)
        ring.layer.borderColor=tint.withAlphaComponent(0.55).cgColor
        orbit.strokeColor=tint.withAlphaComponent(0.85).cgColor;orbitMask.strokeStart=0;orbitMask.strokeEnd=1
        scan.backgroundColor=tint;scan.isHidden=next != .scanning
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        if next == .scanning {
            let line=CABasicAnimation(keyPath:"transform.translation.y")
            line.fromValue = -36;line.toValue=36;line.duration=1.5;line.autoreverses=true;line.repeatCount = .infinity
            line.timingFunction=CAMediaTimingFunction(name:.easeInEaseOut)
            scan.layer.add(line,forKey:"scan")
            orbitMask.strokeEnd=0.27
            let sweep=CABasicAnimation(keyPath:"transform.rotation.z");sweep.fromValue=0;sweep.toValue=Double.pi*2;sweep.duration=1.7;sweep.repeatCount = .infinity
            sweep.timingFunction=CAMediaTimingFunction(name:.linear);orbitMask.add(sweep,forKey:"orbit")
            let pulse=CABasicAnimation(keyPath:"opacity");pulse.fromValue=0.65;pulse.toValue=1
            pulse.duration=1.45;pulse.autoreverses=true;pulse.repeatCount = .infinity
            ring.layer.add(pulse,forKey:"pulse")
        } else if next == .failure {
            let shake=CAKeyframeAnimation(keyPath:"transform.translation.x")
            shake.values=[0,-10,10,-7,7,0];shake.duration=0.36
            ring.layer.add(shake,forKey:"shake")
        } else if next == .success {
            let pop=CAKeyframeAnimation(keyPath:"transform.scale")
            pop.values=[0.90,1.055,1.0];pop.duration=0.62
            ring.layer.add(pop,forKey:"success")
        }
    }
    func systemPromptActive(_ active:Bool){
        // Native Face ID owns its system UI. Keep the custom island and scan out of its way.
        if active {
            stopAnimations()
            islandAuth.alpha=0;ring.alpha=0
            heading.text="Face ID";detail.text="Kijk naar je iPhone om veilig in te loggen."
            code.isEnabled=false
        } else {
            ring.alpha=1;code.isEnabled=true
        }
    }
    func stopAnimations(){ring.layer.removeAllAnimations();scan.layer.removeAllAnimations();orbitMask.removeAllAnimations();islandAuth.reset();ring.alpha=1}
}

final class Panel: UIViewController, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler, URLSessionTaskDelegate {
    let web = WKWebView()
    private let name = UILabel()
    private let firstInstall = UILabel()
    private let recovery = UIButton(type: .system)
    private let faceScreen = FaceLockView(frame: .zero)
    private var loaded = false
    private var generation = 0
    private lazy var client = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: .main)
    private var returning = false
    private var facePending = false
    private var faceBusy = false
    private var faceContext: LAContext?
    private var faceAttempts = 0
    private var faceEnabled: Bool { guard let url=origin else{return false};return UserDefaults.standard.string(forKey:"faceOrigin")==url.absoluteString }
    private var faceAccount: Int { UserDefaults.standard.integer(forKey:"faceAccount") }
    private let faceService = "nl.poldersmp.control.biometric"
    private var faceDevice: String? { UserDefaults.standard.string(forKey:"faceDevice") }
    private func keychainQuery(_ url: URL) -> [String:Any] {
        [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:faceService,kSecAttrAccount as String:url.absoluteString]
    }
    private func deleteFace() {
        if let url=origin { SecItemDelete(keychainQuery(url) as CFDictionary) }
        UserDefaults.standard.removeObject(forKey:"faceOrigin")
        UserDefaults.standard.removeObject(forKey:"faceAccount")
        UserDefaults.standard.removeObject(forKey:"faceDevice");facePending=false
        web.evaluateJavaScript("window.polderNativeBiometric=false;window.polderFaceDeviceId=null;window.polderFaceRetry=false;if(typeof drawLogin==='function')drawLogin();if(typeof render==='function')render()")
    }
    private func storeTicket(_ ticket:String, account:Int, device:String, url:URL) -> Bool {
        guard let access=SecAccessControlCreateWithFlags(nil,kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,.biometryCurrentSet,nil) else{return false}
        var q=keychainQuery(url); SecItemDelete(q as CFDictionary)
        q[kSecAttrAccessControl as String]=access;q[kSecValueData as String]=Data(ticket.utf8)
        guard SecItemAdd(q as CFDictionary,nil)==errSecSuccess else{return false}
        UserDefaults.standard.set(url.absoluteString,forKey:"faceOrigin")
        UserDefaults.standard.set(account,forKey:"faceAccount")
        UserDefaults.standard.set(device,forKey:"faceDevice")
        return true
    }
    private func biometricRequest(_ url:URL,_ path:String,_ payload:[String:Any],session:String?=nil,done:@escaping ([String:Any]?,Int)->Void) {
        var req=URLRequest(url:url.appendingPathComponent("api/"+path),timeoutInterval:10)
        req.httpMethod="POST";req.setValue("application/json",forHTTPHeaderField:"Content-Type")
        if let session=session { req.setValue("Bearer "+session,forHTTPHeaderField:"Authorization") }
        req.httpBody=try? JSONSerialization.data(withJSONObject:payload)
        client.dataTask(with:req){ data,response,_ in
            let body=data.flatMap{try? JSONSerialization.jsonObject(with:$0) as? [String:Any]}
            DispatchQueue.main.async{done(body,(response as? HTTPURLResponse)?.statusCode ?? 0)}
        }.resume()
    }
    private func revokeTicket(_ ticket:String?,at url:URL?) {
        if let ticket=ticket,let url=url { biometricRequest(url,"device-revoke",["ticket":ticket]){_,_ in} }
    }
    private func presentFace() {
        firstInstall.isHidden=true;web.isHidden=true
        faceScreen.alpha=1;faceScreen.isHidden=false
        faceScreen.systemPromptActive(false)
        faceScreen.apply(.waiting,attempt:0)
    }
    private func dismissFace() {
        faceScreen.stopAnimations()
        faceScreen.isHidden=true;faceScreen.alpha=1
    }
    private func skipFace() {
        generation += 1
        faceContext?.invalidate()
        showCode("Gebruik je persoonlijke toegangscode.")
    }
    private func showCode(_ message:String) {
        facePending=false;faceBusy=false;faceContext?.invalidate();faceContext=nil
        dismissFace();firstInstall.isHidden=true;web.isHidden=false
        let data=(try? JSONSerialization.data(withJSONObject:[message])) ?? Data("[]".utf8)
        let json=String(decoding:data,as:UTF8.self)
        web.evaluateJavaScript("window.polderFaceRetry=false;if(typeof polderShowPin==='function')polderShowPin();if(typeof drawLogin==='function')drawLogin();if(typeof byId==='function')byId('auth-result').textContent="+json+"[0]")
    }
    func beginFaceIfNeeded() {
        guard facePending,!faceBusy,loaded,faceEnabled,UIApplication.shared.applicationState == .active,let url=origin else{return}
        facePending=false;faceBusy=true
        let epoch=generation
        let ctx=LAContext();faceContext=ctx
        ctx.localizedFallbackTitle="Gebruik toegangscode"
        ctx.localizedReason="Ontgrendel PolderSMP"
        var error:NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,error:&error),ctx.biometryType == .faceID else{
            showCode("Face ID is niet beschikbaar. Gebruik je persoonlijke code.");return
        }
        faceAttempts += 1
        faceScreen.apply(.scanning,attempt:faceAttempts)
        faceScreen.systemPromptActive(true)
        ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,localizedReason:"Ontgrendel PolderSMP") { success, failure in
            DispatchQueue.main.async {
                guard self.generation==epoch,self.faceBusy else{return}
                self.faceScreen.systemPromptActive(false)
                if !success {
                    self.faceBusy=false;self.faceContext=nil
                    if (failure as? LAError)?.code == .authenticationFailed {
                        self.faceScreen.apply(.failure,attempt:self.faceAttempts)
                        DispatchQueue.main.asyncAfter(deadline:.now()+0.7){
                            guard self.generation==epoch,!self.faceBusy,!self.faceScreen.isHidden else{return}
                            if self.faceAttempts<3 { self.facePending=true;self.beginFaceIfNeeded() }
                            else { self.showCode("Gebruik je persoonlijke toegangscode om in te loggen.") }
                        }
                    } else { self.showCode("Gebruik je persoonlijke toegangscode om in te loggen.") }
                    return
                }
                // Reuse the already authenticated context; never display a second biometric dialog.
                ctx.interactionNotAllowed=true
                var q=self.keychainQuery(url)
                q[kSecReturnData as String]=true
                q[kSecMatchLimit as String]=kSecMatchLimitOne
                q[kSecUseAuthenticationContext as String]=ctx
                let query=q
                DispatchQueue.global(qos:.userInitiated).async{
                    var item:CFTypeRef?
                    let status=SecItemCopyMatching(query as CFDictionary,&item)
                    let token=(item as? Data).flatMap{String(data:$0,encoding:.utf8)}
                    DispatchQueue.main.async{
                        guard self.generation==epoch,self.faceBusy else{return}
                        guard status==errSecSuccess,let token=token else{
                            self.showCode("Face ID-koppeling niet beschikbaar. Gebruik je code en stel Face ID opnieuw in.");return
                        }
                        self.biometricRequest(url,"device-login",["ticket":token]){body,status in
                            guard self.generation==epoch,self.faceBusy else{return}
                            guard status==200,let session=body?["session"] as? String else{
                                if status==401 { self.deleteFace() }
                                self.showCode("Face ID-aanmelding niet beschikbaar. Gebruik je code.");return
                            }
                            self.faceBusy=false;self.faceContext=nil
                            let json=String(decoding:(try? JSONSerialization.data(withJSONObject:[session])) ?? Data("[]".utf8),as:UTF8.self)
                            self.web.evaluateJavaScript("typeof nativeUnlock==='function' && (nativeUnlock("+json+"[0]),true)"){result,error in
                                guard self.generation==epoch else{return}
                                if error != nil || result as? Bool != true { self.showCode("Open het bijgewerkte PolderBeheer en log in met je code.") }
                                else {
                                    self.faceScreen.apply(.success,attempt:self.faceAttempts)
                                    DispatchQueue.main.asyncAfter(deadline:.now()+0.55){
                                        guard self.generation==epoch else{return}
                                        self.firstInstall.isHidden=true;self.web.isHidden=false
                                        if UIAccessibility.isReduceMotionEnabled { self.dismissFace() }
                                        else { UIView.animate(withDuration:0.44,delay:0,options:[.curveEaseInOut,.beginFromCurrentState],animations:{self.faceScreen.alpha=0}){_ in
                                            guard self.generation==epoch else{return};self.dismissFace()
                                        } }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    private func enrollFace(_ session:String,account:Int) {
        guard account>0,!session.isEmpty,origin != nil,presentedViewController==nil else{return}
        let ctx=LAContext();var err:NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,error:&err),ctx.biometryType == .faceID else{info("Stel Face ID eerst in via de instellingen van je iPhone.");return}
        let epoch=generation
        let guide=FaceGuideController{[weak self] confirmed in
            guard let self=self,confirmed,self.generation==epoch,!self.returning else{return}
            self.confirmFaceEnrollment(session,account:account)
        }
        present(guide,animated:!UIAccessibility.isReduceMotionEnabled)
    }
    private func confirmFaceEnrollment(_ session:String,account:Int) {
        guard let url=origin,account>0,!session.isEmpty,presentedViewController==nil else{return}
        let ctx=LAContext()
        var error:NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,error:&error),ctx.biometryType == .faceID else{info("Stel Face ID eerst in via de instellingen van je iPhone.");return}
        let alert=UIAlertController(title:"Face ID inschakelen",message:"Voer één keer je persoonlijke toegangscode in. Daarna bevestig je met Face ID.",preferredStyle:.alert)
        alert.addTextField{ $0.isSecureTextEntry=true;$0.keyboardType = .numberPad;$0.placeholder="Toegangscode" }
        alert.addAction(UIAlertAction(title:"Annuleren",style:.cancel))
        alert.addAction(UIAlertAction(title:"Ga door",style:.default){ _ in
            let code=alert.textFields?.first?.text ?? ""
            let epoch=self.generation
            self.biometricRequest(url,"device-enroll",["code":code],session:session){body,status in
                guard self.generation==epoch else{self.revokeTicket(body?["ticket"] as? String,at:url);return}
                guard status==200,let ticket=body?["ticket"] as? String,let ident=body?["account"] as? Int,ident==account,let device=body?["device"] as? String else{self.info(body?["error"] as? String ?? "Face ID instellen mislukt. Controleer PolderBeheer.");return}
                ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,localizedReason:"Bevestig Face ID voor PolderSMP"){ok,_ in
                    DispatchQueue.main.async{
                        guard self.generation==epoch else{self.revokeTicket(ticket,at:url);return}
                        let old=self.faceDevice
                        guard ok,self.storeTicket(ticket,account:ident,device:device,url:url) else{self.revokeTicket(ticket,at:url);self.info("Face ID kon niet worden ingesteld. Je code blijft werken.");return}
                        if let old=old { self.biometricRequest(url,"device-forget",["device":old],session:session){_,_ in} }
                        self.web.evaluateJavaScript("window.polderNativeBiometric=true;window.polderFaceDeviceId='"+device+"';rememberSession('');render()")
                        self.info("Face ID is ingeschakeld. De volgende keer wordt je gezicht gecontroleerd.")
                    }
                }
            }
        })
        present(alert,animated:true)
    }
    func lockForReturn() {
        generation += 1
        presentedViewController?.dismiss(animated: false)
        returning = true
        faceContext?.invalidate();faceContext=nil;faceBusy=false;facePending=false
        web.isHidden = true
        dismissFace()
        if faceEnabled { web.evaluateJavaScript("if(typeof disconnect==='function')disconnect('',true)") }
    }
    func reopenLogin() {
        guard returning else { return }
        returning = false
        if loaded {
            if faceEnabled {
                faceAttempts=0;facePending=false;web.isHidden=true
                presentFace()
                web.evaluateJavaScript("if(typeof disconnect==='function')disconnect('',true)"){_,_ in self.facePending=true;self.beginFaceIfNeeded()}
            } else { web.isHidden=false;web.evaluateJavaScript("if(typeof refresh==='function')refresh()") }
        } else if let url = origin { openPanel(url) }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if UIApplication.shared.applicationState != .background {
            returning = false
            loaded = true
            if faceEnabled {
                faceAttempts=0;facePending=true;web.isHidden=true
                presentFace()
                beginFaceIfNeeded()
            } else { firstInstall.isHidden=true;web.isHidden=false }
        }
    }
    var origin: URL? { UserDefaults.standard.url(forKey: "panel") }
    private func openPanel(_ url: URL) {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        components.path = "/"
        components.query = nil
        components.fragment = nil
        guard let root = components.url else { return }
        loaded = false
        dismissFace()
        web.isHidden = true
        installScripts()
        web.load(URLRequest(url: root, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15))
    }
    override func loadView() {
        let screen = UIView()
        screen.backgroundColor = .systemBackground
        let icon = UIImageView(image: Bundle.main.path(forResource: "AppIcon60@2x", ofType: "png").flatMap { UIImage(contentsOfFile: $0) })
        icon.contentMode = .scaleAspectFit
        icon.layer.cornerRadius = 7
        icon.clipsToBounds = true
        icon.widthAnchor.constraint(equalToConstant: 30).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 30).isActive = true
        name.text = "PolderSMP / Atlas"
        name.font = .systemFont(ofSize:18,weight:.semibold)
        name.adjustsFontForContentSizeCategory = true
        let brand = UIStackView(arrangedSubviews: [icon, name])
        brand.spacing = 10
        brand.alignment = .center
        brand.translatesAutoresizingMaskIntoConstraints = false
        screen.addSubview(brand)
        recovery.setImage(UIImage(systemName: "arrow.clockwise.circle"), for: .normal)
        recovery.tintColor = .systemBlue
        recovery.accessibilityLabel = "Verbinding herstellen"
        recovery.addTarget(self, action: #selector(recoverConnection), for: .touchUpInside)
        recovery.translatesAutoresizingMaskIntoConstraints = false
        screen.addSubview(recovery)
        firstInstall.text = "Welkom bij PolderSMP\n\nTik op het verbindingsicoon of open een koppellink van je eigenaar. Log daarna in met je eigen code."
        firstInstall.numberOfLines = 0
        firstInstall.textAlignment = .center
        firstInstall.font = .preferredFont(forTextStyle: .body)
        firstInstall.isHidden = origin != nil
        firstInstall.translatesAutoresizingMaskIntoConstraints = false
        screen.addSubview(firstInstall)
        web.isHidden = origin == nil
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.translatesAutoresizingMaskIntoConstraints = false
        screen.addSubview(web)
        faceScreen.translatesAutoresizingMaskIntoConstraints=false
        faceScreen.isHidden=true
        faceScreen.useCode={ [weak self] in self?.skipFace() }
        screen.addSubview(faceScreen)
        NSLayoutConstraint.activate([
            faceScreen.topAnchor.constraint(equalTo:screen.topAnchor),faceScreen.bottomAnchor.constraint(equalTo:screen.bottomAnchor),
            faceScreen.leadingAnchor.constraint(equalTo:screen.leadingAnchor),faceScreen.trailingAnchor.constraint(equalTo:screen.trailingAnchor),
            brand.topAnchor.constraint(equalTo: screen.safeAreaLayoutGuide.topAnchor, constant: 8),
            brand.leadingAnchor.constraint(equalTo: screen.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            brand.trailingAnchor.constraint(lessThanOrEqualTo: recovery.leadingAnchor, constant: -8),
            recovery.trailingAnchor.constraint(equalTo: screen.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            recovery.centerYAnchor.constraint(equalTo: brand.centerYAnchor),
            recovery.widthAnchor.constraint(equalToConstant: 44),
            recovery.heightAnchor.constraint(equalToConstant: 44),
            firstInstall.centerYAnchor.constraint(equalTo: screen.safeAreaLayoutGuide.centerYAnchor),
            firstInstall.leadingAnchor.constraint(equalTo: screen.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            firstInstall.trailingAnchor.constraint(equalTo: screen.safeAreaLayoutGuide.trailingAnchor, constant: -32),
            web.topAnchor.constraint(equalTo: recovery.bottomAnchor, constant: 4),
            web.bottomAnchor.constraint(equalTo: screen.safeAreaLayoutGuide.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: screen.safeAreaLayoutGuide.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: screen.safeAreaLayoutGuide.trailingAnchor)
        ])
        view = screen
    }
    private func installScripts() {
        let controller=web.configuration.userContentController
        controller.removeAllUserScripts()
        if let file=Bundle.main.url(forResource:"client-style",withExtension:"js"),let script=try? String(contentsOf:file,encoding:.utf8){ controller.addUserScript(WKUserScript(source:script,injectionTime:.atDocumentEnd,forMainFrameOnly:true)) }
        controller.addUserScript(WKUserScript(source:"window.polderNativeBiometric="+(faceEnabled ? "true":"false")+";window.polderFaceRetry=false;window.polderFaceDeviceId="+(faceDevice.map{"'"+$0+"'"} ?? "null")+";",injectionTime:.atDocumentStart,forMainFrameOnly:true))
        web.configuration.userContentController.addUserScript(WKUserScript(source: """
        document.documentElement.setAttribute('data-iphone','');

        window.polderShowPin=function(){
            const form=document.getElementById('login'),input=document.getElementById('key'),signin=document.getElementById('signin');
            if(!form||!input||!signin||form.querySelector('.polder-pin-pad')||typeof legacy==='undefined'||legacy||setup)return;
            const style=document.createElement('style');
            style.textContent='.polder-pin-pad{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:9px;margin:8px 0 2px}.polder-pin-pad button{font-size:23px;font-weight:500;min-height:52px;border-radius:16px;background:var(--bg);touch-action:manipulation;transition:transform .13s}.polder-pin-pad button:active{transform:scale(.93)}.polder-pin-pad .pin-special{font-size:13px;font-weight:600}.polder-pin-intro{font-size:13px;color:var(--muted);margin:0}.polder-pin-shake{animation:polderShake .35s ease}@keyframes polderShake{0%,100%{transform:translateX(0)}25%,75%{transform:translateX(-7px)}50%{transform:translateX(7px)}}@media(prefers-reduced-motion:reduce){.polder-pin-pad button{transition:none}.polder-pin-shake{animation:none}}';
            document.head.append(style);
            const intro=document.createElement('p');intro.className='polder-pin-intro';intro.textContent='6–10 cijfers · Beveiligde toegang';
            const pad=document.createElement('div');pad.className='polder-pin-pad';pad.setAttribute('role','group');pad.setAttribute('aria-label','Numeriek toetsenbord');
            const tap=()=>window.webkit.messageHandlers.biometric.postMessage({action:'pin-tap'});
            const update=()=>input.dispatchEvent(new Event('input',{bubbles:true}));
            const add=(label,action,special=false)=>{
                const b=document.createElement('button');b.type='button';b.textContent=label;
                if(special)b.className='pin-special';
                b.addEventListener('click',()=>{if(signin.disabled)return;tap();action()});pad.append(b);return b;
            };
            for(let n=1;n<=9;n++)add(String(n),()=>{if(input.value.length<10){input.value+=String(n);update()}});
            add('Wis',()=>{input.value='';update()},true);
            add('0',()=>{if(input.value.length<10){input.value+='0';update()}});
            const del=add('⌫',()=>{input.value=input.value.slice(0,-1);update()},true);del.setAttribute('aria-label','Verwijder laatste cijfer');
            input.setAttribute('inputmode','none');input.setAttribute('autocomplete','off');
            signin.before(intro,pad);
            const status=document.getElementById('auth-result');
            if(status)new MutationObserver(()=>{if(!status.textContent||!form.isConnected||signin.hidden)return;pad.classList.remove('polder-pin-shake');void pad.offsetWidth;pad.classList.add('polder-pin-shake')}).observe(status,{childList:true,characterData:true,subtree:true});
            const legacyButton=document.getElementById('legacy');
            if(legacyButton)legacyButton.addEventListener('click',()=>{pad.hidden=legacy;intro.hidden=legacy;input.setAttribute('inputmode',legacy?'text':'none')});
        };

        if (typeof settings === 'function') {
            const originalSettings = settings;
            settings = function() {
                originalSettings();
                if (owner() && settingsTab === 'Account') {
                    const section = node('section','','card');
                    section.append(node('h2','Verbinding'),node('p','Privéadres van de server-pc','secondary'),button('Serveradres wijzigen',()=>window.webkit.messageHandlers.connection.postMessage('open')));
                    content.append(section);
                }
            };
        }
        """, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        web.uiDelegate = self
        web.navigationDelegate = self
        for handler in ["connection", "panelTheme", "biometric"] {
            web.configuration.userContentController.add(self, name: handler)
        }
        if let url = origin { openPanel(url) }
    }

    @objc private func recoverConnection() {
        guard !returning, faceScreen.isHidden, presentedViewController == nil else { return }
        if loaded {
            web.evaluateJavaScript("typeof key !== 'undefined' && !!key") { active, error in
                guard error == nil, active as? Bool == false else {
                    self.info("Wijzig het adres via Instellingen als hoofdeigenaar, of log uit om de lokale koppeling te herstellen.")
                    return
                }
                self.recoveryDialog()
            }
        } else { recoveryDialog() }
    }
    private func recoveryDialog() {
        let alert = UIAlertController(title: "Verbinding herstellen", message: "Huidig adres: " + (origin?.absoluteString ?? "Niet gekoppeld") + "\n\nControleer Tailscale en het serveradres.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Annuleren", style: .cancel))
        if let url = origin {
            alert.addAction(UIAlertAction(title: "Opnieuw verbinden", style: .default) { _ in self.openPanel(url) })
            alert.addAction(UIAlertAction(title: "Lokale koppeling wissen", style: .destructive) { _ in
                self.generation += 1
                self.deleteFace()
                self.loaded = false
                self.web.stopLoading()
                self.web.isHidden = true
                UserDefaults.standard.removeObject(forKey: "panel")
                self.firstInstall.text = "Open een koppellink of tik op het wifi-icoon om een adres in te voeren."
                self.firstInstall.isHidden = false
            })
        } else {
            alert.addAction(UIAlertAction(title: "Adres invoeren", style: .default) { _ in self.initialAddress() })
        }
        present(alert, animated: true)
    }
    private func initialAddress() {
        let a = UIAlertController(title: "Server koppelen", message: "Vul het privé HTTPS-adres in.", preferredStyle: .alert)
        a.addTextField { $0.keyboardType = .URL; $0.autocapitalizationType = .none; $0.autocorrectionType = .no }
        a.addAction(UIAlertAction(title: "Annuleren", style: .cancel))
        a.addAction(UIAlertAction(title: "Verbinden", style: .default) { _ in
            guard self.origin == nil, let url = self.address(a.textFields?.first?.text ?? "") else { self.info("Ongeldig Tailscale HTTPS-adres."); return }
            self.probe(url) { ok in
                if ok && self.origin == nil { self.save(url) }
                else { self.info("Geen verbinding met PolderBeheer. Controleer Tailscale en het adres.") }
            }
        })
        present(a, animated: true)
    }

    private func color(_ text: Any?) -> UIColor? {
        guard let hex = text as? String, hex.count == 7, hex.first == "#",
              let n = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return UIColor(red: CGFloat(n >> 16) / 255, green: CGFloat(n >> 8 & 255) / 255, blue: CGFloat(n & 255) / 255, alpha: 1)
    }
    private func address(_ text: String) -> URL? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var c = URLComponents(string: value.contains("://") ? value : "https://" + value),
              c.scheme == "https", c.host?.lowercased().hasSuffix(".ts.net") == true,
              c.user == nil, c.password == nil, c.path.isEmpty || c.path == "/",
              c.fragment == nil, c.query == nil else { return nil }
        c.path = "/"
        return c.url
    }
    func pair(_ link: URL) -> Bool {
        guard link.scheme == "poldersmp", link.host == "koppel", origin == nil,
              let text = URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "adres" })?.value,
              let url = address(text) else { return false }
        loadViewIfNeeded()
        probe(url) { ok in
            guard self.origin == nil else { return }
            if ok { self.save(url) } else { self.info("Koppelen mislukt. Controleer Tailscale en open de koppellink opnieuw.") }
        }
        return true
    }
    private func save(_ url: URL) {
        generation += 1
        if origin != url { deleteFace() }
        UserDefaults.standard.set(url, forKey: "panel")
        firstInstall.isHidden = true
        web.isHidden = true
        openPanel(url)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
    private func probe(_ url: URL, completion: @escaping (Bool) -> Void) {
        var request = URLRequest(url: url.appendingPathComponent("api/login-info"), timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        client.dataTask(with: request) { data, response, _ in
            let body = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String:Any] }
            DispatchQueue.main.async { completion((response as? HTTPURLResponse)?.statusCode == 200 && body?["needsStation"] is Bool && body?["setup"] is Bool) }
        }.resume()
    }
    private func withOwner(_ action: @escaping () -> Void) {
        let epoch = generation
        guard let base = origin, !returning else { return }
        web.evaluateJavaScript("typeof owner === 'function' && owner() ? key : ''") { result, _ in
            guard self.generation == epoch, let token = result as? String, !token.isEmpty else { return }
            var request = URLRequest(url: base.appendingPathComponent("api/access"), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            self.client.dataTask(with: request) { data, response, _ in
                let record = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String:Any] }
                let owner = (response as? HTTPURLResponse)?.statusCode == 200 && record?["role"] as? String == "owner"
                DispatchQueue.main.async {
                    guard self.generation == epoch, !self.returning else { return }
                    self.web.evaluateJavaScript("typeof owner === 'function' && owner() ? key : ''") { current, _ in
                        guard self.generation == epoch, current as? String == token else { return }
                        if owner { action() } else { self.info("De server-pc kon je eigenaarstoegang niet bevestigen.") }
                    }
                }
            }.resume()
        }
    }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let base = origin, let source = message.frameInfo.request.url,
              source.scheme == "https", source.host == base.host, source.port == base.port else { return }
        if message.name == "panelTheme", let theme = message.body as? [String:Any] {
            view.backgroundColor = color(theme["background"])
            name.textColor = color(theme["ink"])
            overrideUserInterfaceStyle = theme["dark"] as? Bool == true ? .dark : .light
        } else if message.name=="biometric",let body=message.body as? [String:Any],let action=body["action"] as? String {
            if action=="pin-tap" { UISelectionFeedbackGenerator().selectionChanged() }
            else if action=="enroll",let session=body["session"] as? String,let account=body["account"] as? Int,!returning,!faceBusy { enrollFace(session,account:account) }
            else if action=="disable" || action=="logout" {
                if action=="disable",let url=origin,let device=faceDevice,let session=body["session"] as? String { biometricRequest(url,"device-forget",["device":device],session:session){_,_ in} }
                deleteFace()
            } else if action=="code-login",let account=body["account"] as? Int,faceEnabled,account != faceAccount {
                deleteFace()
            }
        } else if message.name == "connection", presentedViewController == nil {
            withOwner { if self.presentedViewController == nil { self.connect() } }
        }
    }
    private func connect() {
        guard let current = origin else { return }
        let alert = UIAlertController(title: "Verbinding", message: "Dit is het privéadres van je server-pc.", preferredStyle: .alert)
        alert.addTextField { field in
            field.text = current.absoluteString; field.keyboardType = .URL; field.autocapitalizationType = .none; field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Annuleren", style: .cancel))
        alert.addAction(UIAlertAction(title: "Kopieer koppellink", style: .default) { _ in
            self.withOwner {
                var parts = URLComponents()
                parts.scheme = "poldersmp"; parts.host = "koppel"; parts.queryItems = [URLQueryItem(name: "adres", value: current.absoluteString)]
                UIPasteboard.general.string = parts.string
                self.info("Koppellink gekopieerd. Deel hem met een nieuwe iPhone. Iedereen logt in met een eigen code.")
            }
        })
        alert.addAction(UIAlertAction(title: "Adres opslaan", style: .default) { _ in
            guard let url = self.address(alert.textFields?.first?.text ?? "") else { self.info("Vul het HTTPS-adres van Tailscale Serve in, inclusief een eventueel poortnummer."); return }
            self.probe(url) { ok in
                guard !self.returning else { return }
                self.withOwner {
                    if ok { self.web.evaluateJavaScript("lockPanel()") { _, _ in self.save(url) } }
                    else { self.info("Geen PolderSMP-paneel gevonden. Je huidige adres blijft ingesteld.") }
                }
            }
        })
        present(alert, animated: true)
    }
    func info(_ message: String, done: @escaping () -> Void = {}) {
        let a = UIAlertController(title: "PolderSMP", message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in done() })
        present(a, animated: true)
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let u = action.request.url
        decisionHandler(u?.scheme == "https" && u?.host == origin?.host && u?.port == origin?.port ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled {
            returning = false; loaded = false; web.isHidden = true; dismissFace()
            firstInstall.text = "Pc onbereikbaar. Tik op het wifi-icoon om je verbinding te herstellen."
            firstInstall.isHidden = false
            info("Verbinding mislukt: " + error.localizedDescription)
        }
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) { info(message, done: completionHandler) }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: message, message: nil, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Annuleren", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "Bevestigen", style: .default) { _ in completionHandler(true) })
        present(a, animated: true)
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let a = UIAlertController(title: prompt, message: nil, preferredStyle: .alert)
        a.addTextField { $0.text = defaultText }
        a.addAction(UIAlertAction(title: "Annuleren", style: .cancel) { _ in completionHandler(nil) })
        a.addAction(UIAlertAction(title: "Versturen", style: .default) { _ in completionHandler(a.textFields?.first?.text) })
        present(a, animated: true)
    }
}
