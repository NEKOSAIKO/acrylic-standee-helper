# 亚克力立牌助手 Windows 预览版 0.1

这是首个可操作桌面演示，适合验证 PNG、刀线和底座；**尚不能用于生产导出**。Mac 0.2.7 保持原样。

## 打开与使用

1. 将 Windows ZIP **完整解压**到可写文件夹，双击 `亚克力立牌助手.exe`。不要单独移动 EXE。包内自带 Electron 和 Clipper2 DLL，不要求用户安装 Node、Python、.NET SDK 或 Illustrator。
2. 点击“打开 PNG…”选择透明 PNG，或点击“示例图”。也可把 PNG 文件拖到 EXE 上，通过启动参数导入。允许中文和空格路径；原图上限 6000 万像素。全透明图、无效 PNG 会提示错误。超大图的内存压力尚未完成验收，建议先使用普通尺寸图。
3. 在“刀线”页调整高度、透明边、平滑和 CNC 跨接参数；松开滑块或结束数值编辑后计算。“查看跨接”显示位置，右侧可逐处取消或保留。
4. 在“底座”页设置底座、厚度与插脚。独立青蓝参考框不合入粉色主体刀线；顶部默认额外延展 3 mm。插槽宽＝插脚宽＋修正，高＝材料厚度＋修正。越界或相交时底座停止预览并显示错误。
5. “白墨”页显示原尺寸覆盖蒙版。勾选画笔后单击或拖动补白；笔径以毫米显示，笔迹按原图归一化坐标保存。黑色仅代表白墨覆盖预览，不能当作 CMYK K100 生产文件。
6. 滚轮缩放，普通拖动平移；启用画笔时按住 **Alt 拖动**平移。“适合画布”复位，“实际尺寸”按 Windows 96 逻辑像素/英寸显示，未经显示器物理校准；“像素细节”按一个原图像素对应一个逻辑显示像素查看。
7. **Ctrl+Z** 撤销参数或画笔操作。“恢复默认设置”保留图片、项目名、备注和笔迹，且可撤销。重新导入图片清除笔迹和撤销历史。
8. 高级设置默认收起，展开状态会记住；收起不改变参数。主题跟随系统。右上角“使用教程”提供八步整窗遮罩引导，目标控件可以操作，Esc 退出；退出恢复原查看页，保留主动修改的参数。

## 本版边界

- 原像素白墨：自动实白/跟随透明度、阈值、补白蒙版预览已实现。**白墨内缩、填孔、矢量白墨、CMYK K100 资源及六页 CMYK PDF 尚未移植完成。**
- “导出 PDF”“生成 .ai 文件”目前只显示未完成说明，不保存文件，也不启动 Illustrator。没有把 RGB 或改名 PDF 当成 AI。
- 没有项目保存/恢复，关闭后图片、笔迹、项目名和备注不会恢复。本预览版也不能通过导出保存这些内容。
- 八步引导可手动重看；暂不在首次启动自动弹出。高 DPI、多显示器、长时间大图操作和干净系统仍待全面验收。
- 本包未做发布者代码签名。目标为 Windows x64；当前只在 Windows 11 build 26200 实测，Windows 10 和 ARM64 未验证。

## 开发与复现

源码以 GitHub 提交 `9f64997d0305ebf300d752035c562906f3cf8d0c` 为基线，独立分支 `windows/desktop-preview`，新增代码均在 `windows/`。原 Mac 源码、构建和发布脚本不变。

开发依赖：Node 22.12+、pnpm、Zig 0.14.1 Windows x64（或后续验证的兼容 C++17 工具链）。在 `windows/` 中：

```powershell
pnpm install --frozen-lockfile --ignore-scripts
node node_modules/electron/install.js
./build-native.ps1 -Zig C:/tools/zig/zig.exe
node tests/core.cjs
pnpm start
node package.cjs
```

Koffi 2.15.1 已带 Windows x64 预编译 N-API 模块，无需执行其编译安装脚本。Electron 固定 44.2.0，依赖锁文件随源码保存。`package.cjs` 输出便携目录到 `windows/dist/`，保留 Electron/Chromium、Koffi、Clipper2 许可证。输出已存在时脚本拒绝覆盖。

`electron . --smoke` 在真实 Electron 渲染进程中解码示例并运行接口检查，输出 `smoke-result.json` 与 `smoke.png` 后退出。`tests/core.cjs` 覆盖独立参考框、延展、换图缓存和插槽边界，输出 `tests/results.json`。这些检查不调用 Illustrator。

## 后续移植路线

1. 用同一分析 alpha 输入对照 Mac 和 Windows，定位跨接数及拟合节点差异，建立几何回归样本。
2. 按 `src/WhiteInk.swift` 复现原像素填孔/内缩核与边界处理，验证画笔裁剪、撤销、尺寸变化和大图取消。
3. 移植 `CMYKPDF.swift` / `ExportPackage.swift`，保留 schema 3 和真实 CMYK + alpha，保留原 `illustrator-helper.jsx`。
4. 用户授权具体 Windows 导出验收后，再实现/检查 Illustrator 自动化、毫米、双画板、图层、嵌入与 K100。失败降级到手动 JSX 包时必须明确说明。
5. 补齐 DPI、纯净系统、代码签名和发布检查，之后通过现有 GitHub 项目新增 Windows 资产；不覆盖 Mac 下载，也不把未验收版标为正式最新版。

技术依据：[Electron 上下文隔离](https://www.electronjs.org/docs/latest/tutorial/context-isolation)、[Zig 编译工具](https://ziglang.org/download/)。界面是随 EXE 打包的本地页面，无本地 HTTP 服务，不加载远端页面，生产几何在独立 Worker 中调用原生 DLL。
