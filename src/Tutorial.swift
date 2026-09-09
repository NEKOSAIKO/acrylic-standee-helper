import AppKit

private final class TutorialCard:NSView {
    override var isFlipped:Bool{true}
    override func draw(_ dirtyRect:NSRect){
        NSColor.windowBackgroundColor.setFill();NSBezierPath(roundedRect:bounds,xRadius:16,yRadius:16).fill()
    }
    override func viewDidChangeEffectiveAppearance(){super.viewDidChangeEffectiveAppearance();needsDisplay=true}
}

final class TutorialOverlay:NSView {
    let card:NSView=TutorialCard()
    var targets:[NSView]=[]
    private(set) var holes:[CGRect]=[]
    var advance:(()->Void)?,retreat:(()->Void)?,close:(()->Void)?
    override var isFlipped:Bool{true}
    override var acceptsFirstResponder:Bool{true}
    override init(frame:NSRect){
        super.init(frame:frame);autoresizingMask=[.width,.height];wantsLayer=true
        card.wantsLayer=true;card.layer?.shadowColor=NSColor.black.cgColor;card.layer?.shadowOpacity=0.4;card.layer?.shadowRadius=18;card.layer?.shadowOffset=CGSize(width:0,height:-5);addSubview(card)
    }
    required init?(coder:NSCoder){fatalError()}
    func refresh(){
        let nextHoles=targets.compactMap{view->CGRect? in
            guard view.window===window,!view.isHiddenOrHasHiddenAncestor else{return nil}
            let visible=view.visibleRect.intersection(view.bounds)
            guard visible.width>1,visible.height>1 else{return nil}
            return convert(visible,from:view).insetBy(dx:-6,dy:-6).intersection(bounds.insetBy(dx:4,dy:4))
        }.filter{!$0.isNull && !$0.isEmpty}
        let oldFrame=card.frame,oldHoles=holes
        holes=[]
        for rect in nextHoles {
            var combined=rect
            while let i=holes.firstIndex(where:{$0.intersects(combined)}){combined=combined.union(holes.remove(at:i))}
            holes.append(combined)
        }
        let width:CGFloat=min(350,bounds.width-32),height:CGFloat=240
        let anchor=holes.reduce(CGRect.null){$0.union($1)}
        var x:CGFloat,y:CGFloat
        if anchor.isNull{x=(bounds.width-width)/2;y=(bounds.height-height)/2}
        else if anchor.maxY<130{x=anchor.maxX-width;y=anchor.maxY+22}
        else if anchor.minX>width+36{x=anchor.minX-width-24;y=anchor.midY-height/2}
        else if bounds.width-anchor.maxX>width+36{x=anchor.maxX+24;y=anchor.midY-height/2}
        else{x=anchor.midX-width/2;y=anchor.maxY+20}
        x=max(16,min(x,bounds.width-width-16));y=max(16,min(y,bounds.height-height-16))
        card.frame=CGRect(x:x,y:y,width:width,height:height)
        if card.frame != oldFrame{card.needsLayout=true}
        if holes != oldHoles || card.frame != oldFrame{needsDisplay=true}
    }
    override func layout(){super.layout();refresh()}
    override func draw(_ dirtyRect:NSRect){
        let shade=NSBezierPath(rect:bounds);shade.windingRule = .evenOdd
        for rect in holes{shade.append(NSBezierPath(roundedRect:rect,xRadius:8,yRadius:8))}
        NSColor.black.withAlphaComponent(0.70).setFill();shade.fill()
        for rect in holes {
            let ring=NSBezierPath(roundedRect:rect,xRadius:8,yRadius:8)
            NSColor.systemPurple.setStroke();ring.lineWidth=5;ring.stroke()
            NSColor.white.withAlphaComponent(0.95).setStroke();ring.lineWidth=1.5;ring.stroke()
        }
        guard let target=holes.first else{return}
        let box=card.frame
        let start:CGPoint,end:CGPoint
        if box.maxX<target.minX{start=CGPoint(x:box.maxX,y:box.midY);end=CGPoint(x:target.minX-5,y:target.midY)}
        else if box.minX>target.maxX{start=CGPoint(x:box.minX,y:box.midY);end=CGPoint(x:target.maxX+5,y:target.midY)}
        else if box.minY>target.maxY{start=CGPoint(x:min(max(target.midX,box.minX+18),box.maxX-18),y:box.minY);end=CGPoint(x:target.midX,y:target.maxY+5)}
        else{start=CGPoint(x:box.midX,y:box.maxY);end=CGPoint(x:target.midX,y:target.minY-5)}
        let line=NSBezierPath();line.move(to:start);line.line(to:end);line.lineWidth=2;NSColor.white.withAlphaComponent(0.85).setStroke();line.stroke()
    }
    override func hitTest(_ point:NSPoint)->NSView?{
        let p=convert(point,from:superview)
        if card.frame.contains(p){return super.hitTest(point)}
        if holes.contains(where:{$0.contains(p)}){return nil}
        return bounds.contains(p) ? self:nil
    }
    override func mouseDown(with event:NSEvent){window?.makeFirstResponder(self)}
    override func scrollWheel(with event:NSEvent){}
    override func keyDown(with event:NSEvent){
        switch event.keyCode{case 53:close?();case 36,124:advance?();case 123:retreat?();default:super.keyDown(with:event)}
    }
}

final class StandeeTutorial:NSObject {
    struct Step{let title:String;let body:String;let tip:String}
    static let steps:[Step]=[
        Step(title:"1. 导入透明 PNG",body:"点击高亮的「打开 PNG…」选择图片。也可以先看完整个教程，再开始制作。",tip:"高亮控件可以直接操作；按「下一步」继续。"),
        Step(title:"2. 定尺寸与透明边",body:"这里设置主体高度和图案外的透明边。画布上的粉色线就是成品刀线。",tip:"尺寸统一使用毫米；调整后预览会自动更新。"),
        Step(title:"3. 用画笔补白墨",body:"勾选这里开启补白画笔，再在画布缺墨处点击或拖涂。黑色表示白墨覆盖。",tip:"需要实际补画时，可先结束教程；画笔直径在开关下方。"),
        Step(title:"4. 设置底座",body:"先选择圆形或方形底座，再设置底座宽度。厚度和插槽参数在同一页。",tip:"圆形底座的宽度就是直径。"),
        Step(title:"5. 调整插脚参考",body:"这里设置蓝色参考框的宽度与左右位置。参考框独立于主体刀线，由工厂调整连接。",tip:"蓝框标位置；底座插槽仍由尺寸参数生成。"),
        Step(title:"6. 需要时展开高级",body:"勾选这里可展开精细参数，包括跨接阈值、白墨内缩、双插脚和插槽尺寸修正。",tip:"收起高级设置会保留已设置的数值。"),
        Step(title:"7. 填写工厂备注",body:"填写项目名称和需要工厂注意的事项，随图稿一起交付。",tip:"例如：插脚由工厂调整、材料厚度或装配要求。"),
        Step(title:"8. 导出制作文件",body:"点击「生成 .ai 文件」或「导出 PDF」。AI 默认毫米，并带独立图层和工厂说明。",tip:"关闭软件前请导出结果；「使用教程」可随时重看。")
    ]
    let overlay=TutorialOverlay(frame:.zero)
    let previous=NSButton(title:"上一步",target:nil,action:nil),next=NSButton(title:"下一步",target:nil,action:nil),skip=NSButton(title:"结束引导",target:nil,action:nil)
    private let heading=NSTextField(labelWithString:""),body=NSTextField(wrappingLabelWithString:""),tip=NSTextField(wrappingLabelWithString:""),progress=NSTextField(labelWithString:"")
    private(set) var index=0
    var prepare:((Int)->[NSView])?,dismissed:(()->Void)?
    private var timer:Timer?
    private var finished=false
    override init(){
        super.init()
        let stack=NSStackView();stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=12;stack.translatesAutoresizingMaskIntoConstraints=false;overlay.card.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:overlay.card.leadingAnchor,constant:18),stack.trailingAnchor.constraint(equalTo:overlay.card.trailingAnchor,constant:-18),stack.topAnchor.constraint(equalTo:overlay.card.topAnchor,constant:18),stack.bottomAnchor.constraint(equalTo:overlay.card.bottomAnchor,constant:-18)])
        progress.font = .systemFont(ofSize:11,weight:.medium);progress.textColor = .secondaryLabelColor
        heading.font = .systemFont(ofSize:18,weight:.semibold);body.font = .systemFont(ofSize:13);tip.font = .systemFont(ofSize:11);tip.textColor = .secondaryLabelColor
        for label in [progress,heading,body,tip]{stack.addArrangedSubview(label);label.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true;label.setContentCompressionResistancePriority(.required,for:.vertical)}
        let space=NSView();space.setContentHuggingPriority(.defaultLow,for:.vertical);stack.addArrangedSubview(space)
        for b in [previous,next,skip]{b.bezelStyle = .rounded;b.target=self;b.controlSize = .small}
        previous.action=#selector(back);next.action=#selector(forward);skip.action=#selector(finish)
        let gap=NSView();gap.setContentHuggingPriority(.defaultLow,for:.horizontal)
        let actions=NSStackView(views:[skip,gap,previous,next]);actions.orientation = .horizontal;actions.spacing=6;stack.addArrangedSubview(actions);actions.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
        overlay.advance={[weak self] in self?.forward()};overlay.retreat={[weak self] in self?.back()};overlay.close={[weak self] in self?.finish()}
        update()
    }
    func present(on window:NSWindow){
        guard let root=window.contentView else{return};overlay.frame=root.bounds;root.addSubview(overlay,positioned:.above,relativeTo:nil);update();window.makeFirstResponder(overlay)
        let timer=Timer(timeInterval:0.15,repeats:true){[weak self] _ in self?.overlay.refresh()};self.timer=timer;RunLoop.main.add(timer,forMode:.common)
    }
    func update(){
        let step=Self.steps[index];progress.stringValue="操作引导  ·  \(index+1) / \(Self.steps.count)";heading.stringValue=step.title;body.stringValue=step.body;tip.stringValue=step.tip
        previous.isEnabled=index>0;next.title=index==Self.steps.count-1 ? "完成":"下一步"
        if overlay.superview != nil{overlay.targets=prepare?(index) ?? [];overlay.superview?.layoutSubtreeIfNeeded();overlay.refresh();overlay.layoutSubtreeIfNeeded()}
    }
    @objc func back(){guard index>0 else{return};index-=1;update()}
    @objc func forward(){if index==Self.steps.count-1{finish()}else{index+=1;update()}}
    @objc func finish(){guard !finished else{return};finished=true;timer?.invalidate();timer=nil;let window=overlay.window;overlay.removeFromSuperview();window?.makeFirstResponder(nil);dismissed?()}
    deinit{timer?.invalidate()}
}
