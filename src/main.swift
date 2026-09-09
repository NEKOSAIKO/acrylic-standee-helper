import AppKit
import UniformTypeIdentifiers
class TopAlignedView:NSView {override var isFlipped:Bool{true}}
final class DropView:TopAlignedView {
    override var isOpaque:Bool{true}
    override func draw(_ dirtyRect:NSRect){NSColor.windowBackgroundColor.setFill();bounds.fill()}
    override func viewDidChangeEffectiveAppearance(){super.viewDidChangeEffectiveAppearance();needsDisplay=true}
    var accept:((URL)->Void)?
    override init(frame:NSRect){super.init(frame:frame);registerForDraggedTypes([.fileURL])}
    required init?(coder:NSCoder){fatalError()}
    override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation{.copy}
    override func performDragOperation(_ sender:NSDraggingInfo)->Bool{guard let list=sender.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL],let url=list.first else{return false};accept?(url);return true}
}
final class StandeeApp:NSObject,NSApplicationDelegate,NSTextFieldDelegate {
    var window:NSWindow!,settings=StandeeSettings(),art:LoadedArtwork?,result:GeometryResult?,white:WhiteInk?
    let canvas=StandeeCanvas(),filename=NSTextField(labelWithString:"拖入透明 PNG，开始制版"),meta=NSTextField(labelWithString:"原图像素 · 毫米尺寸 · CMYK"),status=NSTextField(wrappingLabelWithString:""),measure=NSTextField(labelWithString:"")
    let mode=NSSegmentedControl(labels:["成品","刀线","白墨","填孔"],trackingMode:.selectOne,target:nil,action:nil)
    let section=NSSegmentedControl(labels:["刀线","白墨","底座","交付"],trackingMode:.selectOne,target:nil,action:nil)
    let pdfButton=NSButton(title:"导出 PDF",target:nil,action:nil),aiButton=NSButton(title:"生成 .ai 文件",target:nil,action:nil)
    let progress=NSProgressIndicator(),compare=NSButton(checkboxWithTitle:"修改前后对比",target:nil,action:nil)
    let bridge=NSButton(checkboxWithTitle:"自动跨接深凹口",target:nil,action:nil),whiteFill=NSButton(checkboxWithTitle:"填满白墨内部镂空",target:nil,action:nil),whiteVector=NSButton(checkboxWithTitle:"改用矢量实白（导出时拟合）",target:nil,action:nil)
    let alphaMode=NSPopUpButton(),shape=NSPopUpButton(),tabCount=NSPopUpButton()
    let whiteBrush=NSButton(checkboxWithTitle:"启用补白画笔",target:nil,action:nil)
    let undoBrushButton=NSButton(title:"撤销上一笔",target:nil,action:nil),clearBrushButton=NSButton(title:"清空手动补白",target:nil,action:nil)
    let brushStatus=NSTextField(wrappingLabelWithString:"尚无手动补白")
    let jobName=NSTextField(string:"亚克力立牌"),notes=NSTextField(wrappingLabelWithString:"")
    let detail=NSButton(title:"查看跨接",target:nil,action:nil),next=NSButton(title:"下一处",target:nil,action:nil),toggleBridge=NSButton(title:"取消这一处跨接",target:nil,action:nil)
    let bridgeActions=NSStackView()
    let advanced=NSButton(checkboxWithTitle:"高级设置",target:nil,action:nil)
    var advancedViews:[NSView]=[],tutorial:StandeeTutorial?
    var parameterBlocks:[String:NSView]=[:],tutorialImport:NSView?
    let advancedKeys:Set<String>=["cornerRadius","bridgeWidth","notchDepth","whiteInset","threshold","tabOverlap","fit","factoryDPI"]
    var fields:[String:NSTextField]=[:],sliders:[String:NSSlider]=[:],ranges:[String:ClosedRange<Double>]=[:],steps:[String:Double]=[:],groups:[NSStackView]=[]
    var completedSettings:StandeeSettings?
    var loadingArtwork=false,resetButton:NSButton?
    var cancellation:Cancellation?,pending:DispatchWorkItem?,generation=0,history:[StandeeSettings]=[],lastHistory=Date.distantPast,previousExport:PreparedExport?,exporting=false
    let queue=DispatchQueue(label:"cn.neko.standee.compute",qos:.userInitiated)
    var resources:URL {Bundle.main.resourceURL!}
    lazy var engine=GeometryEngine(engineURL:resources.appendingPathComponent("acrylic-geometry.js"))
    let whiteEngine=WhiteEngine()
    func applicationDidFinishLaunching(_ n:Notification){buildMenu();buildWindow();let args=CommandLine.arguments
        if let i=args.firstIndex(of:"--initial-height"),i+1<args.count,let h=Double(args[i+1]),(50...300).contains(h){settings.height=h;syncControls()}
        if let i=args.firstIndex(of:"--open-image"),i+1<args.count{load(URL(fileURLWithPath:args[i+1]))}else{load(resources.appendingPathComponent("sample.png"))};NSApp.activate(ignoringOtherApps:true)
        if !args.contains("--startup-check"),!UserDefaults.standard.bool(forKey:"tutorialSeenV2"){DispatchQueue.main.async{self.showTutorial()}}
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool{true}
    func buildMenu(){let bar=NSMenu(),a=NSMenuItem(),f=NSMenuItem(),e=NSMenuItem();bar.addItem(a);bar.addItem(f);bar.addItem(e);a.submenu=NSMenu();a.submenu!.addItem(withTitle:"退出亚克力立牌助手",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q");f.submenu=NSMenu(title:"文件");for (t,action,key) in [("打开 PNG…",#selector(openImage),"o"),("生成 .ai 文件…",#selector(exportAI),"s"),("导出 CMYK PDF…",#selector(exportPDF),"e")]{f.submenu!.addItem(withTitle:t,action:action,keyEquivalent:key).target=self};e.submenu=NSMenu(title:"编辑");e.submenu!.addItem(withTitle:"撤销操作",action:#selector(undo),keyEquivalent:"z").target=self;for(t,action,key) in [("复制",#selector(NSText.copy(_:)),"c"),("粘贴",#selector(NSText.paste(_:)),"v"),("全选",#selector(NSText.selectAll(_:)),"a")]{e.submenu!.addItem(withTitle:t,action:action,keyEquivalent:key)};let help=NSMenuItem();bar.addItem(help);help.submenu=NSMenu(title:"帮助");help.submenu!.addItem(withTitle:"使用教程",action:#selector(showTutorial),keyEquivalent:"").target=self;NSApp.mainMenu=bar}
    func buildWindow(show:Bool=true){
        window=NSWindow(contentRect:NSRect(x:0,y:0,width:1280,height:900),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false);window.title="亚克力立牌助手 0.2";window.minSize=NSSize(width:1040,height:740);window.center()
        let root=DropView();root.accept={[weak self] in self?.load($0)};root.wantsLayer=true;window.contentView=root
        let head=NSView(),left=NSView(),scroll=NSScrollView();for v in [head,left,scroll]{v.translatesAutoresizingMaskIntoConstraints=false;root.addSubview(v)};scroll.hasVerticalScroller=true;scroll.backgroundColor = .controlBackgroundColor
        NSLayoutConstraint.activate([head.leadingAnchor.constraint(equalTo:root.leadingAnchor),head.trailingAnchor.constraint(equalTo:root.trailingAnchor),head.topAnchor.constraint(equalTo:root.topAnchor),head.heightAnchor.constraint(equalToConstant:90),left.leadingAnchor.constraint(equalTo:root.leadingAnchor),left.topAnchor.constraint(equalTo:head.bottomAnchor),left.bottomAnchor.constraint(equalTo:root.bottomAnchor),left.trailingAnchor.constraint(equalTo:scroll.leadingAnchor),scroll.topAnchor.constraint(equalTo:head.bottomAnchor),scroll.bottomAnchor.constraint(equalTo:root.bottomAnchor),scroll.trailingAnchor.constraint(equalTo:root.trailingAnchor),scroll.widthAnchor.constraint(equalToConstant:348)])
        let logo=NSTextField(labelWithString:"亚克力立牌"),version=NSTextField(labelWithString:"STANDEE STUDIO  /  0.2.7");logo.font = .systemFont(ofSize:25,weight:.semibold);version.font = .systemFont(ofSize:10,weight:.semibold);version.textColor = .secondaryLabelColor
        let brand=NSStackView(views:[logo,version]);brand.orientation = .vertical;brand.alignment = .leading;brand.spacing=5
        let open=button("打开 PNG…",#selector(openImage)),sample=button("示例图",#selector(loadSample));tutorialImport=open;pdfButton.target=self;pdfButton.action=#selector(exportPDF);aiButton.target=self;aiButton.action=#selector(exportAI)
        for b in [pdfButton,aiButton]{b.bezelStyle = .rounded;b.controlSize = .large};aiButton.bezelColor=NSColor(calibratedRed:0.39,green:0.29,blue:0.75,alpha:1);aiButton.contentTintColor = .white
        let spacer=NSView();spacer.setContentHuggingPriority(.defaultLow,for:.horizontal)
        let appIcon=NSImageView();appIcon.image=NSImage(named:"AppIcon");appIcon.imageScaling = .scaleProportionallyUpOrDown;appIcon.widthAnchor.constraint(equalToConstant:48).isActive=true;appIcon.heightAnchor.constraint(equalToConstant:48).isActive=true
        let identity=NSStackView(views:[appIcon,brand]);identity.orientation = .horizontal;identity.spacing=10
        let row=NSStackView(views:[identity,spacer,button("使用教程",#selector(showTutorial)),open,sample,pdfButton,aiButton]);row.orientation = .horizontal;row.spacing=12;row.translatesAutoresizingMaskIntoConstraints=false;head.addSubview(row);NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo:head.leadingAnchor,constant:24),row.trailingAnchor.constraint(equalTo:head.trailingAnchor,constant:-24),row.centerYAnchor.constraint(equalTo:head.centerYAnchor)])
        filename.font = .systemFont(ofSize:15,weight:.semibold);filename.lineBreakMode = .byTruncatingMiddle;meta.font = .systemFont(ofSize:11);meta.textColor = .secondaryLabelColor
        mode.selectedSegment=0;mode.target=self;mode.action=#selector(changeView);compare.state = .on;compare.target=self;compare.action=#selector(changeView)
        detail.target=self;detail.action=#selector(detailAction);next.target=self;next.action=#selector(nextAction);toggleBridge.target=self;toggleBridge.action=#selector(toggleRegion);for b in [detail,next,toggleBridge]{b.bezelStyle = .rounded};next.isHidden=true;toggleBridge.isHidden=true
        let views=NSStackView(views:[mode,compare,detail]);views.orientation = .horizontal;views.spacing=14
        bridgeActions.addArrangedSubview(next);bridgeActions.addArrangedSubview(toggleBridge);bridgeActions.orientation = .horizontal;bridgeActions.spacing=8;bridgeActions.isHidden=true
        let controls=NSStackView(views:[views,bridgeActions]);controls.orientation = .vertical;controls.alignment = .leading;controls.spacing=8
        let zoom=NSStackView(views:[button("适合画布",#selector(fitView)),button("实际尺寸",#selector(actualSize)),button("像素细节",#selector(pixelDetail))]);zoom.orientation = .horizontal;zoom.spacing=8;zoom.setHuggingPriority(.required,for:.horizontal);zoom.setContentCompressionResistancePriority(.required,for:.horizontal);zoom.widthAnchor.constraint(equalToConstant:zoom.arrangedSubviews.reduce(16){$0+$1.intrinsicContentSize.width}).isActive=true
        canvas.whiteStrokeCommitted={[weak self] stroke in self?.commitWhiteStroke(stroke)};canvas.wantsLayer=true;canvas.layer?.cornerRadius=14;canvas.layer?.masksToBounds=true;canvas.bridgeSelected={[weak self] i in self?.canvas.detailIndex=i;self?.canvas.fitView();self?.refreshDetail()}
        measure.font = .monospacedDigitSystemFont(ofSize:12,weight:.medium);status.font = .systemFont(ofSize:11);status.maximumNumberOfLines=3;status.textColor = .secondaryLabelColor
        progress.style = .spinning;progress.controlSize = .small;progress.isDisplayedWhenStopped=false
        for v in [filename,meta,controls,zoom,canvas,measure,status,progress]{v.translatesAutoresizingMaskIntoConstraints=false;left.addSubview(v)}
        NSLayoutConstraint.activate([
            filename.leadingAnchor.constraint(equalTo:left.leadingAnchor,constant:24),filename.topAnchor.constraint(equalTo:left.topAnchor,constant:7),filename.trailingAnchor.constraint(equalTo:left.trailingAnchor,constant:-24),
            meta.leadingAnchor.constraint(equalTo:filename.leadingAnchor),meta.topAnchor.constraint(equalTo:filename.bottomAnchor,constant:5),
            controls.leadingAnchor.constraint(equalTo:filename.leadingAnchor),controls.topAnchor.constraint(equalTo:meta.bottomAnchor,constant:16),controls.trailingAnchor.constraint(lessThanOrEqualTo:filename.trailingAnchor),
            canvas.leadingAnchor.constraint(equalTo:left.leadingAnchor,constant:16),canvas.trailingAnchor.constraint(equalTo:left.trailingAnchor,constant:-16),canvas.topAnchor.constraint(equalTo:controls.bottomAnchor,constant:12),canvas.bottomAnchor.constraint(equalTo:measure.topAnchor,constant:-12),
            measure.leadingAnchor.constraint(equalTo:filename.leadingAnchor),measure.trailingAnchor.constraint(equalTo:filename.trailingAnchor),measure.bottomAnchor.constraint(equalTo:status.topAnchor,constant:-7),
            zoom.trailingAnchor.constraint(equalTo:left.trailingAnchor,constant:-24),zoom.centerYAnchor.constraint(equalTo:status.centerYAnchor),
            status.leadingAnchor.constraint(equalTo:filename.leadingAnchor),status.trailingAnchor.constraint(equalTo:zoom.leadingAnchor,constant:-36),status.bottomAnchor.constraint(equalTo:left.bottomAnchor,constant:-16),status.heightAnchor.constraint(equalToConstant:44),
            progress.trailingAnchor.constraint(equalTo:zoom.leadingAnchor,constant:-10),progress.topAnchor.constraint(equalTo:status.topAnchor),progress.widthAnchor.constraint(equalToConstant:16)
        ])
        let doc=TopAlignedView(),column=NSStackView();doc.translatesAutoresizingMaskIntoConstraints=false;scroll.documentView=doc;column.orientation = .vertical;column.alignment = .leading;column.spacing=18;column.edgeInsets=NSEdgeInsets(top:16,left:20,bottom:24,right:20);column.translatesAutoresizingMaskIntoConstraints=false;doc.addSubview(column);NSLayoutConstraint.activate([doc.widthAnchor.constraint(equalTo:scroll.widthAnchor),column.leadingAnchor.constraint(equalTo:doc.leadingAnchor),column.trailingAnchor.constraint(equalTo:doc.trailingAnchor),column.topAnchor.constraint(equalTo:doc.topAnchor),column.bottomAnchor.constraint(equalTo:doc.bottomAnchor)])
        section.selectedSegment=0;section.target=self;section.action=#selector(changeSection);column.addArrangedSubview(section);section.widthAnchor.constraint(equalTo:column.widthAnchor,constant:-40).isActive=true
        let resetButton=button("恢复默认设置",#selector(restoreDefaults));self.resetButton=resetButton;resetButton.setAccessibilityIdentifier("restore-defaults");resetButton.toolTip="恢复制版参数，保留原图、项目备注和手动补白；可撤销。"
        advanced.target=self;advanced.action=#selector(toggleAdvanced);advanced.state=UserDefaults.standard.bool(forKey:"advancedControlsVisible") ? .on:.off;advanced.toolTip="展开精细参数；收起时保留已经设置的值。"
        let actionSpacer=NSView();actionSpacer.setContentHuggingPriority(.defaultLow,for:.horizontal)
        let settingsActions=NSStackView(views:[advanced,actionSpacer,resetButton]);settingsActions.orientation = .horizontal;settingsActions.spacing=8;column.addArrangedSubview(settingsActions);settingsActions.widthAnchor.constraint(equalTo:column.widthAnchor,constant:-40).isActive=true
        for _ in 0..<4{let g=NSStackView();g.orientation = .vertical;g.alignment = .leading;g.spacing=16;column.addArrangedSubview(g);g.widthAnchor.constraint(equalTo:column.widthAnchor,constant:-40).isActive=true;groups.append(g)}
        title("轮廓与透明边",in:0);hint("先调整大小，再决定曲线和跨接。",in:0)
        number("height","主体高度",150,50...300,1,"mm",0);number("offset","最小透明边",3,0...10,0.1,"mm",0);number("curveSmooth","曲线平滑",60,0...100,1,"",0);hint("保留细节  ←  →  更顺滑\n整段贝塞尔拟合；拖动后自动更新。",in:0);number("cornerRadius","凹角圆滑 R",1,0...5,0.1,"mm",0)
        title("CNC 凹口跨接",in:0);bridge.state = .on;configure(bridge,#selector(checkChanged),0);number("toolDiameter","刀具直径",3,0.5...8,0.1,"mm",0);number("bridgeWidth","跨接开口上限",16,3...30,0.5,"mm",0);number("notchDepth","凹口深度阈值",1,0...5,0.1,"mm",0);hint("点击画布上的跨接位置，可单独保留或取消。耳朵等需要保留的开口请逐处检查。",in:0)
        title("手动补白",in:1);configure(whiteBrush,#selector(toggleWhiteBrush),1)
        number("whiteBrushSize","画笔直径",2,0.2...15,0.1,"mm",1)
        undoBrushButton.target=self;undoBrushButton.action=#selector(undoWhiteStroke);clearBrushButton.target=self;clearBrushButton.action=#selector(clearWhiteStrokes)
        undoBrushButton.bezelStyle = .rounded;clearBrushButton.bezelStyle = .rounded
        let brushActions=NSStackView(views:[undoBrushButton,clearBrushButton]);brushActions.orientation = .horizontal;brushActions.spacing=8;groups[1].addArrangedSubview(brushActions)
        brushStatus.font = .systemFont(ofSize:11);brushStatus.textColor = .secondaryLabelColor;groups[1].addArrangedSubview(brushStatus)
        hint("启用后在白墨视图点击或拖涂，补足缺墨和小孔。黑色表示实白；淡彩图仅辅助定位。Option 拖动画布。补白保留原像素并进入 AI / PDF。",in:1)
        title("原图精度白墨",in:1);hint("直接读取原图透明度；预览缩略图不会用于白墨导出。",in:1);alphaMode.addItems(withTitles:["实白底 · 保留抗锯齿边缘","跟随原图透明度"]);alphaMode.target=self;alphaMode.action=#selector(checkChanged);groups[1].addArrangedSubview(alphaMode);advancedViews.append(alphaMode);number("whiteInset","白墨内缩",0,0...0.5,0.01,"mm",1);configure(whiteFill,#selector(checkChanged),1);configure(whiteVector,#selector(checkChanged),1);advancedViews.append(whiteVector);number("threshold","图案透明度阈值",10,1...90,1,"%",1);hint("黑色仅表示白墨覆盖。透明度、内缩和矢量实白可在高级设置中调整。",in:1)
        title("插脚与底座",in:2);number("thickness","立牌厚度",3,1...10,0.1,"mm",2);shape.addItems(withTitles:["◯  圆形底座","▭  长方形底座","□  正方形底座"]);shape.target=self;shape.action=#selector(checkChanged);groups[2].addArrangedSubview(shape);number("baseWidth","底座宽度 / 直径",65,30...160,1,"mm",2);number("baseLength","底座深度",45,30...160,1,"mm",2);number("tabDepth","底座厚度 / 插入深度",3,1...10,0.1,"mm",2);tabCount.addItems(withTitles:["单插脚","双插脚"]);tabCount.target=self;tabCount.action=#selector(checkChanged);groups[2].addArrangedSubview(tabCount);advancedViews.append(tabCount);number("tabWidth","插脚参考宽度",18,8...45,0.5,"mm",2);number("tabPosition","插脚参考位置",0,-70...70,1,"%",2);number("tabOverlap","参考框向上延展",3,0...15,0.5,"mm",2);number("fit","插槽尺寸修正",0,-0.3...0.5,0.01,"mm",2);hint("插脚以独立矩形标位置，由工厂调整并连接主体。底座插槽保持原有生成方式。",in:2)
        title("工厂交付说明",in:3);hint("AI 附独立说明画板；PDF 附第 6 页说明。生产图稿保持毫米原尺寸。",in:3)
        let nameTitle=NSTextField(labelWithString:"项目 / 款式名称");groups[3].addArrangedSubview(nameTitle);jobName.delegate=self;jobName.target=self;jobName.action=#selector(textChanged);groups[3].addArrangedSubview(jobName);jobName.widthAnchor.constraint(equalTo:groups[3].widthAnchor).isActive=true
        let noteTitle=NSTextField(labelWithString:"给工厂的备注");groups[3].addArrangedSubview(noteTitle);notes.isEditable=true;notes.isSelectable=true;notes.isBezeled=true;notes.drawsBackground=true;notes.delegate=self;notes.font = .systemFont(ofSize:12);groups[3].addArrangedSubview(notes);notes.widthAnchor.constraint(equalTo:groups[3].widthAnchor).isActive=true;notes.heightAnchor.constraint(equalToConstant:100).isActive=true
        number("factoryDPI","分辨率参考值",350,150...600,10,"ppi",3);hint("输出：CMYK / 原像素彩稿 / K100 白墨\n方向：按原稿方向，未自动镜像\nAI：彩稿、白墨、主体刀线、插脚参考、底座、说明\nPDF：四页生产图稿 + 插脚参考页 + 说明",in:3);groups[3].addArrangedSubview(button("打开上次 AI 资料包",#selector(revealPackage)))
        let undoButton=button("撤销操作  ⌘Z",#selector(undo));column.addArrangedSubview(undoButton);changeSection();syncControls();applyAdvancedVisibility();if show{window.makeKeyAndOrderFront(nil)}
    }
    func applyAdvancedVisibility(){for view in advancedViews{view.isHidden=advanced.state != .on}}
    @objc func toggleAdvanced(){
        window.makeFirstResponder(nil)
        do{_ = try readSettings()}catch{advanced.state = .on;fail("请先修正参数，再收起高级设置。")}
        applyAdvancedVisibility();UserDefaults.standard.set(advanced.state == .on,forKey:"advancedControlsVisible")
    }
    func makeTutorial(markSeen:Bool)->StandeeTutorial {
        let savedSection=section.selectedSegment,savedMode=mode.selectedSegment,savedBrush=whiteBrush.state,savedDetail=canvas.detailIndex
        let guide=StandeeTutorial()
        guide.prepare={[weak self] index in self?.prepareTutorialStep(index) ?? []}
        guide.dismissed={[weak self] in
            guard let self=self else{return}
            self.section.selectedSegment=savedSection;self.changeSection();self.mode.selectedSegment=savedMode;self.changeView();self.whiteBrush.state=savedBrush;self.updateBrushControls();self.canvas.detailIndex=savedDetail;self.refreshDetail()
            if markSeen{UserDefaults.standard.set(true,forKey:"tutorialSeenV2")}
            self.tutorial=nil
        }
        return guide
    }
    func prepareTutorialStep(_ index:Int)->[NSView] {
        let pages:[Int?]=[nil,0,1,2,2,nil,3,nil]
        if let page=pages[index]{section.selectedSegment=page;changeSection();mode.selectedSegment=page==1 ? 2:0;changeView();canvas.detailIndex=nil;refreshDetail()}
        let targets:[NSView]
        switch index {
        case 0:targets=[tutorialImport].compactMap{$0}
        case 1:targets=[parameterBlocks["height"],parameterBlocks["offset"]].compactMap{$0}
        case 2:targets=[whiteBrush,parameterBlocks["whiteBrushSize"]].compactMap{$0}
        case 3:targets=[shape,parameterBlocks["baseWidth"]].compactMap{$0}
        case 4:targets=[parameterBlocks["tabWidth"],parameterBlocks["tabPosition"]].compactMap{$0}
        case 5:targets=[advanced]
        case 6:targets=[jobName,notes]
        default:targets=[pdfButton,aiButton]
        }
        window.contentView?.layoutSubtreeIfNeeded()
        if let doc=targets.first?.enclosingScrollView?.documentView{
            let area=targets.reduce(CGRect.null){$0.union(doc.convert($1.bounds,from:$1))}
            doc.scrollToVisible(area.insetBy(dx:0,dy:-12))
        }
        window.contentView?.layoutSubtreeIfNeeded()
        return targets
    }
    @objc func showTutorial(){
        guard tutorial==nil,window.attachedSheet==nil else{return}
        let guide=makeTutorial(markSeen:true);tutorial=guide;guide.present(on:window)
    }
    func button(_ title:String,_ action:Selector)->NSButton{let b=NSButton(title:title,target:self,action:action);b.bezelStyle = .rounded;return b}
    func title(_ text:String,in i:Int){let l=NSTextField(labelWithString:text);l.font = .systemFont(ofSize:18,weight:.semibold);groups[i].addArrangedSubview(l)}
    func hint(_ text:String,in i:Int){let l=NSTextField(wrappingLabelWithString:text);l.font = .systemFont(ofSize:11);l.textColor = .secondaryLabelColor;groups[i].addArrangedSubview(l);l.widthAnchor.constraint(equalTo:groups[i].widthAnchor).isActive=true}
    func configure(_ b:NSButton,_ action:Selector,_ i:Int){b.target=self;b.action=action;b.font = .systemFont(ofSize:12);groups[i].addArrangedSubview(b)}
    func number(_ key:String,_ title:String,_ value:Double,_ range:ClosedRange<Double>,_ step:Double,_ unit:String,_ group:Int){
        let label=NSTextField(labelWithString:title);label.font = .systemFont(ofSize:12,weight:.medium);let spacer=NSView();spacer.setContentHuggingPriority(.defaultLow,for:.horizontal)
        let field=NSTextField(string:String(format:"%g",value));field.font = .monospacedDigitSystemFont(ofSize:12,weight:.medium);field.alignment = .right;field.delegate=self;field.target=self;field.action=#selector(textChanged);field.identifier=NSUserInterfaceItemIdentifier(key);field.widthAnchor.constraint(equalToConstant:64).isActive=true
        let units=NSTextField(labelWithString:unit);units.font = .systemFont(ofSize:10);units.textColor = .secondaryLabelColor;units.widthAnchor.constraint(equalToConstant:23).isActive=true
        let row=NSStackView(views:[label,spacer,field,units]);row.orientation = .horizontal;row.spacing=5
        let slider=NSSlider(value:value,minValue:range.lowerBound,maxValue:range.upperBound,target:self,action:#selector(sliderChanged));slider.identifier=NSUserInterfaceItemIdentifier(key);slider.isContinuous=true;slider.setAccessibilityLabel(title);slider.setAccessibilityIdentifier(key+"-slider")
        let block=NSStackView(views:[row,slider]);block.orientation = .vertical;block.alignment = .leading;block.spacing=5;groups[group].addArrangedSubview(block);block.widthAnchor.constraint(equalTo:groups[group].widthAnchor).isActive=true;row.widthAnchor.constraint(equalTo:block.widthAnchor).isActive=true;slider.widthAnchor.constraint(equalTo:block.widthAnchor).isActive=true
        parameterBlocks[key]=block
        if advancedKeys.contains(key){advancedViews.append(block)}
        fields[key]=field;sliders[key]=slider;ranges[key]=range;steps[key]=step
    }
    func remember(force:Bool=false){if force || Date().timeIntervalSince(lastHistory)>0.6{history.append(settings);if history.count>40{history.removeFirst()}};lastHistory=force ? .distantPast:Date()}
    @objc func sliderChanged(_ sender:NSSlider){guard let key=sender.identifier?.rawValue else{return};remember();let step=steps[key] ?? 1,v=(sender.doubleValue/step).rounded()*step;fields[key]?.stringValue=String(format:"%g",v);applyInputs()}
    @objc func textChanged(){remember();applyInputs()}
    func controlTextDidEndEditing(_ obj:Notification){textChanged()}
    @objc func checkChanged(){remember();if whiteVector.state == .on{alphaMode.selectItem(at:0)};applyInputs()}
    func readSettings()throws->StandeeSettings{var s=settings;func val(_ key:String)throws->Double{guard let f=fields[key],let x=Double(f.stringValue.replacingOccurrences(of:",",with:".")),x.isFinite,ranges[key]!.contains(x)else{throw AppFailure("请检查参数数值范围。")};return x}
        s.height=try val("height");s.offset=try val("offset");s.curveSmooth=try val("curveSmooth");s.cornerRadius=try val("cornerRadius");s.toolDiameter=try val("toolDiameter");s.bridgeWidth=try val("bridgeWidth");s.notchDepth=try val("notchDepth");s.thickness=try val("thickness");s.baseWidth=try val("baseWidth");s.baseLength=try val("baseLength");s.tabDepth=try val("tabDepth");s.tabWidth=try val("tabWidth");s.tabPosition=try val("tabPosition");s.tabOverlap=try val("tabOverlap");s.whiteBrushSize=try val("whiteBrushSize");s.fit=try val("fit");s.threshold=try val("threshold");s.whiteInset=try val("whiteInset");s.factoryDPI=try val("factoryDPI")
        s.cncBridge=bridge.state == .on;s.whiteFill=whiteFill.state == .on;s.whiteVector=whiteVector.state == .on;s.whiteFollowsAlpha=alphaMode.indexOfSelectedItem==1 && !s.whiteVector;s.tabCount=tabCount.indexOfSelectedItem+1;s.baseShape=["circle","rectangle","square"][shape.indexOfSelectedItem];s.jobName=jobName.stringValue;s.notes=notes.stringValue;return s}
    func syncControls(){let s=settings,v:[String:Double]=["height":s.height,"offset":s.offset,"curveSmooth":s.curveSmooth,"cornerRadius":s.cornerRadius,"toolDiameter":s.toolDiameter,"bridgeWidth":s.bridgeWidth,"notchDepth":s.notchDepth,"thickness":s.thickness,"baseWidth":s.baseWidth,"baseLength":s.baseLength,"tabDepth":s.tabDepth,"tabWidth":s.tabWidth,"tabPosition":s.tabPosition,"tabOverlap":s.tabOverlap,"whiteBrushSize":s.whiteBrushSize,"fit":s.fit,"threshold":s.threshold,"whiteInset":s.whiteInset,"factoryDPI":s.factoryDPI];for(k,x)in v{fields[k]?.stringValue=String(format:"%g",x);sliders[k]?.doubleValue=x};bridge.state=s.cncBridge ? .on:.off;whiteFill.state=s.whiteFill ? .on:.off;whiteVector.state=s.whiteVector ? .on:.off;alphaMode.selectItem(at:s.whiteFollowsAlpha ? 1:0);shape.selectItem(at:["circle","rectangle","square"].firstIndex(of:s.baseShape) ?? 0);tabCount.selectItem(at:s.tabCount-1);jobName.stringValue=s.jobName;notes.stringValue=s.notes;fields["baseLength"]?.isEnabled=s.baseShape=="rectangle";sliders["baseLength"]?.isEnabled=s.baseShape=="rectangle";alphaMode.isEnabled = !s.whiteVector;updateBrushControls()}
    func applyInputs(){do{let previous=settings;settings=try readSettings();if previous.geometryKey != settings.geometryKey{settings.disabledBridges=[]};for(k,sl)in sliders{sl.doubleValue=Double(fields[k]?.stringValue ?? "") ?? sl.doubleValue};fields["baseLength"]?.isEnabled=settings.baseShape=="rectangle";sliders["baseLength"]?.isEnabled=settings.baseShape=="rectangle";alphaMode.isEnabled = !settings.whiteVector;updateBrushControls()
        let whiteChanged=previous.whiteInset != settings.whiteInset || previous.whiteFill != settings.whiteFill || previous.whiteFollowsAlpha != settings.whiteFollowsAlpha || previous.threshold != settings.threshold
        if previous.geometryKey==settings.geometryKey && !whiteChanged,let r=result{
            canvas.base=settings.basePreview
            if let done=completedSettings,done.geometryKey==settings.geometryKey,done.whiteInset==settings.whiteInset,done.whiteFill==settings.whiteFill,done.whiteFollowsAlpha==settings.whiteFollowsAlpha,done.whiteStrokes==settings.whiteStrokes {showResult(r,elapsed:0)}
            return
        };schedule()
    }catch{fail(error.localizedDescription);pdfButton.isEnabled=false;aiButton.isEnabled=false}}
    func updateBrushControls(){
        whiteBrush.isEnabled=art != nil && result != nil && !exporting && !loadingArtwork
        resetButton?.isEnabled = !loadingArtwork && !exporting
        canvas.brushEnabled=whiteBrush.state == .on && mode.selectedSegment==2 && canvas.detailIndex==nil && completedSettings?.geometryKey==settings.geometryKey && !exporting && !loadingArtwork
        canvas.brushDiameter=settings.whiteBrushSize
        let applied=Set((completedSettings?.whiteStrokes ?? []).map{$0.id})
        canvas.pendingWhiteStrokes=settings.whiteStrokes.filter{!applied.contains($0.id)}
        undoBrushButton.isEnabled = !settings.whiteStrokes.isEmpty && !exporting;clearBrushButton.isEnabled=undoBrushButton.isEnabled
        brushStatus.stringValue=settings.whiteStrokes.isEmpty ? "尚无手动补白":"已补白 \(settings.whiteStrokes.count) 笔 · AI / PDF 将包含补白"
    }
    @objc func toggleWhiteBrush(){
        if whiteBrush.state == .on {mode.selectedSegment=2;if canvas.detailIndex != nil{canvas.detailIndex=nil;canvas.fitView()};changeView();refreshDetail()}
        updateBrushControls()
    }
    func commitWhiteStroke(_ stroke:WhiteBrushStroke){
        guard art != nil,!exporting,!loadingArtwork else{return};remember(force:true);settings.whiteStrokes.append(stroke);updateBrushControls();schedule(delay:0)
    }
    @objc func undoWhiteStroke(){guard !settings.whiteStrokes.isEmpty else{return};remember(force:true);settings.whiteStrokes.removeLast();updateBrushControls();schedule(delay:0)}
    @objc func clearWhiteStrokes(){guard !settings.whiteStrokes.isEmpty else{return};remember(force:true);settings.whiteStrokes=[];updateBrushControls();schedule(delay:0)}
    @objc func restoreDefaults(){guard !loadingArtwork,!exporting else{return};window.makeFirstResponder(nil);remember(force:true);settings=settings.restoringDefaults();whiteBrush.state = .off;canvas.detailIndex=nil;syncControls();schedule(delay:0)}
    @objc func undo(){guard let old=history.popLast()else{return};settings=old;lastHistory = .distantPast;syncControls();schedule()}
    @objc func changeSection(){for(i,g)in groups.enumerated(){g.isHidden=i != section.selectedSegment};if section.selectedSegment != 1{whiteBrush.state = .off};updateBrushControls()}
    @objc func changeView(){canvas.previewMode=["art","cut","white","silhouette"][mode.selectedSegment];canvas.showComparison=compare.state == .on;if mode.selectedSegment != 2{whiteBrush.state = .off};updateBrushControls()}
    @objc func fitView(){canvas.fitView()};@objc func actualSize(){canvas.actualSize()};@objc func pixelDetail(){mode.selectedSegment=2;changeView();canvas.pixelDetail()}
    @objc func detailAction(){whiteBrush.state = .off;updateBrushControls();canvas.detailIndex=canvas.detailIndex == nil ? 0:nil;canvas.fitView();refreshDetail()}
    @objc func nextAction(){let count=result?.model.sortedBridgeRegions.count ?? 0;if count>0{canvas.detailIndex=((canvas.detailIndex ?? 0)+1)%count;canvas.fitView();refreshDetail()}}
    func refreshDetail(){let count=result?.model.sortedBridgeRegions.count ?? 0;if count==0{canvas.detailIndex=nil};detail.title=canvas.detailIndex==nil ? "查看跨接":"返回整体";next.isHidden=canvas.detailIndex==nil;toggleBridge.isHidden=canvas.detailIndex==nil;bridgeActions.isHidden=canvas.detailIndex==nil;detail.isEnabled=count>0;if let i=canvas.detailIndex,let r=result,r.model.sortedBridgeRegions.indices.contains(i){let region=r.model.sortedBridgeRegions[i];toggleBridge.title=region.enabled==false ? "保留这一处跨接":"取消这一处跨接"}}
    @objc func toggleRegion(){guard let i=canvas.detailIndex,let r=result,r.model.sortedBridgeRegions.indices.contains(i)else{return};remember();let id=r.model.sortedBridgeRegions[i].index ?? i;if settings.disabledBridges.contains(id){settings.disabledBridges.removeAll{$0==id}}else{settings.disabledBridges.append(id)};schedule()}
    @objc func openImage(){let panel=NSOpenPanel();panel.allowedContentTypes=[.png];panel.beginSheetModal(for:window){[weak self] response in if response == .OK,let url=panel.url{self?.load(url)}}}
    @objc func loadSample(){load(resources.appendingPathComponent("sample.png"))}
    func load(_ url:URL){loadingArtwork=true;whiteBrush.state = .off;updateBrushControls();pdfButton.isEnabled=false;aiButton.isEnabled=false;cancellation?.cancel();generation+=1;let token=generation;status.stringValue="正在读取原图…";progress.startAnimation(nil);queue.async{let loaded=Result{try LoadedArtwork.load(url)};DispatchQueue.main.async{guard token==self.generation else{return};self.loadingArtwork=false;self.updateBrushControls();switch loaded{case .success(let a):self.art=a;self.result=nil;self.white=nil;self.completedSettings=nil;self.settings.disabledBridges=[];self.settings.whiteStrokes=[];self.history=[];self.lastHistory = .distantPast;self.whiteBrush.state = .off;self.settings.jobName=url.deletingPathExtension().lastPathComponent;self.filename.stringValue=url.lastPathComponent;self.canvas.artwork=a.preview;self.canvas.whiteImage=nil;self.canvas.detailIndex=nil;self.canvas.fitView();self.syncControls();self.schedule(delay:0);case .failure(let e):self.progress.stopAnimation(nil);self.fail(e.localizedDescription)}}}}
    func schedule(delay:Double=0.14){pending?.cancel();cancellation?.cancel();generation+=1;let token=generation,cancel=Cancellation();cancellation=cancel;pdfButton.isEnabled=false;aiButton.isEnabled=false;status.textColor = .secondaryLabelColor;status.stringValue="正在更新；保留上一版预览…";progress.startAnimation(nil);guard let art=art else{return};let s=settings;updateBrushControls()
        let work=DispatchWorkItem{[weak self] in guard let self=self,!cancel.cancelled else{return};let start=Date();let computed=Result{()->(GeometryResult,WhiteInk) in let r=try self.engine.build(art,settings:s,cancellation:cancel);let white=try self.whiteEngine.build(art,settings:s,box:r.model.imageBox,clipPath:r.model.bodyPath,cancellation:cancel);return(r,white)}
            DispatchQueue.main.async{guard token==self.generation else{return};self.progress.stopAnimation(nil);switch computed{case .success(let (r,w)):self.result=r;self.white=w;self.completedSettings=s;self.canvas.geometry=r.model;self.canvas.whiteImage=w.preview;self.updateBrushControls();self.canvas.base=self.settings.basePreview;self.showResult(r,elapsed:Date().timeIntervalSince(start));case .failure(let e):if !e.localizedDescription.contains("CANCELLED"){self.fail(e.localizedDescription)}}}}
        pending=work;queue.asyncAfter(deadline:.now()+delay,execute:work)
    }
    func showResult(_ r:GeometryResult,elapsed:Double){let g=r.model,s=settings;measure.stringValue=String(format:"主体 %0.1f × %0.1f mm   含插脚参考框 %0.1f mm   插槽 %0.2f × %0.2f mm",g.widthMm,g.heightMm,g.totalHeightMm,s.tabWidth+s.fit,s.thickness+s.fit)
        if let a=art{let dpi=Double(a.image.height)/g.imageBox.height*25.4;meta.stringValue="原图 \(a.image.width) × \(a.image.height) px  ·  白墨原像素  ·  约 \(Int(dpi)) ppi"+(dpi<s.factoryDPI ? "  ·  低于参考分辨率":"")}
        let count=(g.bridgeRegions ?? []).filter{$0.enabled != false}.count,unhandled=g.bridgeDiagnostics?.unhandled?.count ?? 0;status.stringValue="已跨接 \(count) 处 · \(unhandled) 处候选待复核 · \(r.json["curveNodes"] as? Int ?? 0) 段曲线"+(elapsed>0 ? String(format:" · 更新 %0.2f 秒",elapsed):" · 底座/说明即时更新")+"\n"+(g.warnings.first ?? "主体刀线不含插脚；蓝框仅定位，由工厂调整并连接主体。")
        status.textColor = .secondaryLabelColor;do{_ = try ExportLayout.make(result:r,settings:s);pdfButton.isEnabled = !exporting;aiButton.isEnabled = !exporting}catch{fail(error.localizedDescription);pdfButton.isEnabled=false;aiButton.isEnabled=false};refreshDetail();updateBrushControls()
        let args=CommandLine.arguments;if let i=args.firstIndex(of:"--startup-check"),i+1<args.count,elapsed>0{
            let proof:[String:Any]=["ready":true,"windowVisible":window.isVisible,"title":window.title,"heightMm":g.heightMm,"bridges":count,"exportEnabled":aiButton.isEnabled]
            do{try JSONSerialization.data(withJSONObject:proof,options:.prettyPrinted).write(to:URL(fileURLWithPath:args[i+1]),options:.withoutOverwriting)}catch{fputs("startup proof failed: \(error)\n",stderr)}
            DispatchQueue.main.async{NSApp.terminate(nil)}
        }
    }
    func fail(_ text:String){status.stringValue=text;status.textColor = .systemRed}
    @objc func exportPDF(){export(ai:false)};@objc func exportAI(){export(ai:true)}
    func export(ai:Bool){window.makeFirstResponder(nil);guard let art=art else{return};let s:StandeeSettings;do{s=try readSettings()}catch{fail(error.localizedDescription);return};let panel=NSSavePanel();panel.allowedContentTypes=ai ? [UTType(filenameExtension:"ai") ?? .data]:[.pdf];panel.nameFieldStringValue=(s.jobName.isEmpty ? "亚克力立牌":s.jobName)+"_\(Int(s.height))mm_0.2.7."+(ai ? "ai":"pdf")
        panel.beginSheetModal(for:window){response in guard response == .OK,let url=panel.url else{return};self.exporting=true;self.updateBrushControls();self.aiButton.isEnabled=false;self.pdfButton.isEnabled=false;self.progress.startAnimation(nil);self.status.stringValue="正在生成原像素 CMYK 文件及工厂说明…";self.status.textColor = .secondaryLabelColor
            self.queue.async{let saved=Result{()->PreparedExport? in let r=try self.engine.build(art,settings:s);var w=try self.whiteEngine.build(art,settings:s,box:r.model.imageBox,clipPath:r.model.bodyPath);if s.whiteVector{w=w.withVector(try self.engine.vectorWhite(w,box:r.model.imageBox))};if ai{return try ExportPackage.make(art:art,result:r,settings:s,white:w,output:url,helper:self.resources.appendingPathComponent("illustrator-helper.jsx"))};try CMYKPDF.export(art:art,result:r,settings:s,white:w,to:url);return nil}
                DispatchQueue.main.async{self.progress.stopAnimation(nil);self.exporting=false;self.updateBrushControls();self.aiButton.isEnabled=true;self.pdfButton.isEnabled=true;switch saved{case .success(let package):if let p=package{self.previousExport=p;self.status.stringValue="资料包已就绪，正在交给 Illustrator…";DispatchQueue.main.asyncAfter(deadline:.now()+0.1){do{_ = try ExportPackage.sendToIllustrator(p);self.status.stringValue="已保存 AI：独立主体刀线、插脚参考图层、原像素彩稿与白墨及工厂说明。";self.status.textColor = .systemGreen}catch{self.fail("自动连接未完成：\(error.localizedDescription)\n资料包已保留，可在 Illustrator → 文件 → 脚本 → 其他脚本打开生成脚本。");NSWorkspace.shared.activateFileViewerSelecting([p.launcher])}}}else{self.status.stringValue="已保存 PDF：4 页生产图稿 + 插脚参考页 + 工厂说明，共 6 页。";self.status.textColor = .systemGreen};case .failure(let e):self.fail(e.localizedDescription)}}
            }
        }
    }
    @objc func revealPackage(){if let p=previousExport{NSWorkspace.shared.activateFileViewerSelecting([p.launcher])}}
}
// Exercises the real view event handlers in an isolated self-test window.
func verifyBrushUI(_ f:StandeeApp)throws {
    guard let r=f.result,let art=f.art else{throw AppFailure("UI fixture missing")}
    func check(_ condition:Bool,_ message:String)throws{if !condition{throw AppFailure("UI: "+message)};print("PASS UI "+message)}
    let g=r.model,body=try SVGPath.parse(g.bodyPath),canvas=f.canvas
    f.section.selectedSegment=1;f.changeSection();f.whiteBrush.state = .on;f.toggleWhiteBrush()
    canvas.zoom=2.1;canvas.pan=CGPoint(x:18,y:-13)
    if let view=f.window.contentView,let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds){view.cacheDisplay(in:view.bounds,to:bitmap)}
    var target:CGPoint?
    for iy in [50]+Array(20...80){for ix in [50]+Array(20...80){let p=CGPoint(x:g.imageBox.x+Double(ix)/100*g.imageBox.width,y:g.imageBox.y+Double(iy)/100*g.imageBox.height);if target==nil && body.contains(p,using:.evenOdd,transform:.identity){target=p}}}
    guard let p=target else{throw AppFailure("UI fixture has no brush target")}
    let zero=canvas.modelPoint(at:.zero),unitX=canvas.modelPoint(at:CGPoint(x:1,y:0)),unitY=canvas.modelPoint(at:CGPoint(x:0,y:1))
    let q=CGPoint(x:(p.x-zero.x)/(unitX.x-zero.x),y:(p.y-zero.y)/(unitY.y-zero.y))
    let before=f.settings.whiteStrokes.count
    func event(_ type:NSEvent.EventType,_ point:CGPoint)->NSEvent{NSEvent.mouseEvent(with:type,location:canvas.convert(point,to:nil),modifierFlags:[],timestamp:0,windowNumber:f.window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!}
    canvas.mouseDown(with:event(.leftMouseDown,q));canvas.mouseUp(with:event(.leftMouseUp,q))
    try check(f.settings.whiteStrokes.count==before+1,"a click commits exactly one brush stroke")
    let first=f.settings.whiteStrokes.last!.points[0]
    try check(abs(first.x-(p.x-g.imageBox.x)/g.imageBox.width)<1e-8 && abs(first.y-(p.y-g.imageBox.y)/g.imageBox.height)<1e-8,"zoom and pan preserve the clicked source coordinate")
    let end=CGPoint(x:q.x+20,y:q.y+12)
    canvas.mouseDown(with:event(.leftMouseDown,q));canvas.mouseDragged(with:event(.leftMouseDragged,end));canvas.mouseUp(with:event(.leftMouseUp,end))
    try check(f.settings.whiteStrokes.count==before+2 && f.settings.whiteStrokes.last!.points.count>1,"a drag commits one continuous stroke")
    f.undoWhiteStroke();try check(f.settings.whiteStrokes.count==before+1,"undo-last-stroke keeps the previous stroke")
    f.clearWhiteStrokes();try check(f.settings.whiteStrokes.isEmpty,"clear button removes manual strokes")
    f.undo();try check(f.settings.whiteStrokes.count==before+1,"general undo restores cleared strokes")
    f.settings.height=220;f.settings.tabOverlap=9;f.settings.whiteBrushSize=8;f.settings.notes="UI keep notes";f.syncControls()
    let prior=f.settings
    f.restoreDefaults();let read=try f.readSettings()
    try check(read.height==150 && read.tabOverlap==3 && read.whiteBrushSize==2 && read.whiteStrokes==prior.whiteStrokes && read.notes==prior.notes && f.art?.id==art.id,"default button synchronizes controls and preserves art, notes and brush edits")
    f.undo();try check(f.settings==prior,"reset defaults is one reversible action")
    f.loadingArtwork=true;f.updateBrushControls();let beforeLoad=f.settings;f.restoreDefaults();f.commitWhiteStroke(WhiteBrushStroke(points:[first],radius:0.01))
    try check(!f.canvas.brushEnabled && f.resetButton?.isEnabled==false && f.settings==beforeLoad,"loading a new image disables painting and reset without changing the current edits")
    f.loadingArtwork=false;f.updateBrushControls();f.pending?.cancel();f.cancellation?.cancel();f.queue.sync{}
}
if CommandLine.arguments.contains("--self-test"){
 do{let args=CommandLine.arguments,resources=Bundle.main.resourceURL!;func arg(_ name:String)->String?{guard let i=args.firstIndex(of:name),i+1<args.count else{return nil};return args[i+1]}
 let url=arg("--image").map{URL(fileURLWithPath:$0)} ?? resources.appendingPathComponent("sample.png"),art=try LoadedArtwork.load(url),engine=GeometryEngine(engineURL:resources.appendingPathComponent("acrylic-geometry.js")),whiteEngine=WhiteEngine();var settings=StandeeSettings();settings.jobName=url.deletingPathExtension().lastPathComponent;if let h=arg("--height").flatMap(Double.init){settings.height=h};if let v=arg("--smooth").flatMap(Double.init){settings.curveSmooth=v};if let v=arg("--inset").flatMap(Double.init){settings.whiteInset=v};settings.whiteFollowsAlpha=args.contains("--follow-alpha");settings.whiteFill=args.contains("--white-fill");settings.whiteVector=args.contains("--vector-white")
 if let v=arg("--tab-width").flatMap(Double.init){settings.tabWidth=v};if let v=arg("--tab-depth").flatMap(Double.init){settings.tabDepth=v};if let v=arg("--tab-overlap").flatMap(Double.init){settings.tabOverlap=v};if let v=arg("--base-width").flatMap(Double.init){settings.baseWidth=v}
 let start=Date(),r=try engine.build(art,settings:settings),geometryMs=Date().timeIntervalSince(start)*1000
 if let brush=arg("--brush-point") {
    let v=brush.split(separator:",").compactMap{Double($0)}
    guard v.count==3,v.allSatisfy({$0.isFinite}),(0...1).contains(v[0]),(0...1).contains(v[1]),v[2]>0,v[2]<=15 else{throw AppFailure("测试画笔参数应为 x比例,y比例,直径mm")}
    settings.whiteStrokes=[WhiteBrushStroke(points:[WhiteBrushPoint(x:v[0],y:v[1])],radius:v[2]/(2*r.model.imageBox.height))]
 }
 let wstart=Date(),w0=try whiteEngine.build(art,settings:settings,box:r.model.imageBox,clipPath:r.model.bodyPath),whiteMs=Date().timeIntervalSince(wstart)*1000
 let w=settings.whiteVector ? w0.withVector(try engine.vectorWhite(w0,box:r.model.imageBox)):w0
 for key in ["bodyPath","bodyOnlyPath","baselinePath"]{let p=try SVGPath.parse(r.json[key] as? String ?? "");guard !p.isEmpty else{throw AppFailure("路径为空")}}
 _ = try ExportLayout.make(result:r,settings:settings);guard w.width==art.image.width,w.height==art.image.height else{throw AppFailure("白墨原始分辨率丢失")}
 if let out=arg("--out"){let dir=URL(fileURLWithPath:out);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);try r.data.write(to:dir.appendingPathComponent("geometry.json"));try CMYKPDF.export(art:art,result:r,settings:settings,white:w,to:dir.appendingPathComponent("standee.pdf"));let p=try ExportPackage.make(art:art,result:r,settings:settings,white:w,output:dir.appendingPathComponent("standee.ai"),helper:resources.appendingPathComponent("illustrator-helper.jsx"));print("JOB \(p.job.path)");if args.contains("--verify-white-pdf"){var job=try JSONSerialization.jsonObject(with:Data(contentsOf:p.job)) as! [String:Any];job["verificationWhitePDF"]=dir.appendingPathComponent("white-from-illustrator.pdf").path;try JSONSerialization.data(withJSONObject:job).write(to:p.job)};if args.contains("--verify-illustrator"){print(try ExportPackage.sendToIllustrator(p))}}
 let cached=Date();_ = try engine.build(art,settings:settings);let cacheMs=Date().timeIntervalSince(cached)*1000
 print("PASS original \(art.image.width)x\(art.image.height); geometry \(Int(geometryMs)) ms; white \(Int(whiteMs)) ms; cache \(cacheMs) ms; nodes \(r.json["curveNodes"] ?? 0); bridges \(r.model.bridgeRegions?.count ?? 0)")
 if let output=arg("--render-ui"){_ = NSApplication.shared;NSApp.appearance=NSAppearance(named:args.contains("--preview-dark") ? .darkAqua:.aqua);let fixture=StandeeApp();fixture.buildWindow(show:false);fixture.settings=settings;fixture.syncControls();fixture.art=art;fixture.result=r;fixture.white=w;fixture.completedSettings=settings;fixture.canvas.artwork=art.preview;fixture.canvas.whiteImage=w.preview;fixture.canvas.geometry=r.model;fixture.canvas.base=settings.basePreview;fixture.filename.stringValue=url.lastPathComponent;fixture.showResult(r,elapsed:(geometryMs+whiteMs)/1000);fixture.window.contentView?.layoutSubtreeIfNeeded()
 if let width=arg("--window-width").flatMap(Double.init),let height=arg("--window-height").flatMap(Double.init){fixture.window.setContentSize(NSSize(width:width,height:height))}
 fixture.advanced.state=args.contains("--preview-advanced") ? .on:.off;fixture.applyAdvancedVisibility()
 if args.contains("--verify-guide") {
    let before=try fixture.readSettings()
    fixture.advanced.state = .off;fixture.applyAdvancedVisibility()
    guard !fixture.advancedViews.isEmpty,fixture.advancedViews.allSatisfy({$0.isHidden}) else{throw AppFailure("高级设置没有隐藏")}
    fixture.advanced.state = .on;fixture.applyAdvancedVisibility()
    guard fixture.advancedViews.allSatisfy({!$0.isHidden}),try fixture.readSettings()==before else{throw AppFailure("展开高级设置改变了参数")}
    fixture.advanced.state = .off;fixture.applyAdvancedVisibility()
    guard try fixture.readSettings()==before else{throw AppFailure("收起高级设置改变了参数")}
    let originalSection=fixture.section.selectedSegment
    let guide=fixture.makeTutorial(markSeen:false);guide.present(on:fixture.window)
    guard !guide.previous.isEnabled else{throw AppFailure("教程首屏错误")}
    guide.forward();guide.back();guard guide.index==0 else{throw AppFailure("教程返回失败")}
    for i in 0..<StandeeTutorial.steps.count {
        guide.overlay.refresh()
        guard !guide.overlay.holes.isEmpty,guide.overlay.bounds.contains(guide.overlay.card.frame) else{throw AppFailure("教程高亮或卡片不在窗口内")}
        for hole in guide.overlay.holes {
            guard !hole.intersects(guide.overlay.card.frame) else{throw AppFailure("教程卡片遮挡高亮控件")}
            let point=CGPoint(x:hole.midX,y:hole.midY)
            guard guide.overlay.hitTest(point)==nil else{throw AppFailure("高亮控件不能点击")}
        }
        if i<StandeeTutorial.steps.count-1{guide.forward()}
    }
    guard guide.next.title=="完成" else{throw AppFailure("教程末屏错误")}
    guide.forward();guard guide.overlay.superview==nil,fixture.section.selectedSegment==originalSection,try fixture.readSettings()==before else{throw AppFailure("教程退出未还原查看状态")}
    print("PASS advanced visibility preserves settings; tutorial navigation and dismissal")
    fixture.advanced.state=args.contains("--preview-advanced") ? .on:.off;fixture.applyAdvancedVisibility()
 }
 if let folder=arg("--render-tutorial") {
    let dir=URL(fileURLWithPath:folder);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
    let guide=fixture.makeTutorial(markSeen:false);guide.present(on:fixture.window)
    for i in 0..<StandeeTutorial.steps.count {
        fixture.window.contentView?.layoutSubtreeIfNeeded();guide.overlay.refresh();guide.overlay.layoutSubtreeIfNeeded()
        if let view=fixture.window.contentView,let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds){view.cacheDisplay(in:view.bounds,to:bitmap);try bitmap.representation(using:.png,properties:[:])!.write(to:dir.appendingPathComponent("step-\(i+1).png"))}
        if i<StandeeTutorial.steps.count-1{guide.forward()}
    }
    guide.finish()
 }

 if args.contains("--verify-appearance") {
    guard fixture.window.appearance == nil else{throw AppFailure("窗口强制了外观")}
    let savedSettings=fixture.settings,savedZoom=fixture.canvas.zoom,savedPan=fixture.canvas.pan
    for name:NSAppearance.Name in [.aqua,.darkAqua,.aqua] {
        NSApp.appearance=NSAppearance(named:name)
        fixture.window.contentView?.layoutSubtreeIfNeeded()
        for view in [fixture.window.contentView!,fixture.canvas,fixture.section] {
            guard view.effectiveAppearance.bestMatch(from:[.aqua,.darkAqua])==name else{throw AppFailure("控件未继承外观")}
        }
        guard fixture.settings==savedSettings,fixture.canvas.zoom==savedZoom,fixture.canvas.pan==savedPan else{throw AppFailure("外观切换改变了编辑状态")}
    }
    NSApp.appearance=NSAppearance(named:args.contains("--preview-dark") ? .darkAqua:.aqua)
    print("PASS appearance light-dark-light inheritance; editing state preserved")
 }
 if args.contains("--verify-ui"){try verifyBrushUI(fixture);fixture.settings=settings;fixture.completedSettings=settings;fixture.result=r;fixture.white=w;fixture.canvas.geometry=r.model;fixture.canvas.whiteImage=w.preview;fixture.canvas.base=settings.basePreview;fixture.canvas.fitView();fixture.progress.stopAnimation(nil);fixture.syncControls();fixture.showResult(r,elapsed:0)}
 if let selected=arg("--preview-section"),let index=["cut","white","base","delivery"].firstIndex(of:selected){fixture.section.selectedSegment=index;fixture.changeSection();if index==1{fixture.whiteBrush.state = .on;fixture.toggleWhiteBrush()}}
 if let width=arg("--window-width").flatMap(Double.init),let height=arg("--window-height").flatMap(Double.init){fixture.window.setContentSize(NSSize(width:width,height:height))}
 if args.contains("--preview-bridge"){fixture.detailAction()}
 fixture.window.contentView?.layoutSubtreeIfNeeded();if let view=fixture.window.contentView,let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds){view.cacheDisplay(in:view.bounds,to:bitmap);try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:output))}}
 }catch{fputs("FAIL: \(error.localizedDescription)\n",stderr);exit(1)};exit(0)
}
let app=NSApplication.shared;app.setActivationPolicy(.regular);let delegate=StandeeApp();app.delegate=delegate;withExtendedLifetime(delegate){app.run()}
