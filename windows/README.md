# 亚克力立牌助手 Windows 预览版 0.1.1-preview.1

本版可导出六页 CMYK PDF，并调用已安装的 Adobe Illustrator 生成原生 AI。已在本机完成实际保存、关闭重开和白墨像素检查；仍需工厂核对与试切。Mac 0.2.7 保持原样。

## 打开与使用

1. 将 Windows ZIP **完整解压**到可写文件夹，双击 `亚克力立牌助手.exe`。不要单独移动 EXE。包内自带 Electron 和 Clipper2 DLL，不要求用户安装 Node、Python、.NET SDK 或 Illustrator。
2. 点击“打开 PNG…”选择透明 PNG，或点击“示例图”。也可把 PNG 文件拖到 EXE 上，通过启动参数导入。允许中文和空格路径；原图上限 6000 万像素。全透明图、无效 PNG 会提示错误。超大图的内存压力尚未完成验收，建议先使用普通尺寸图。
3. 在“刀线”页调整高度、透明边、平滑和 CNC 跨接参数；松开滑块或结束数值编辑后计算。“查看跨接”显示位置，右侧可逐处取消或保留。
4. 在“底座”页设置底座、厚度与插脚。独立青蓝参考框不合入粉色主体刀线；顶部默认额外延展 3 mm。插槽宽＝插脚宽＋修正，高＝材料厚度＋修正。越界或相交时底座停止预览并显示错误。
5. “白墨”页显示原尺寸覆盖蒙版。勾选画笔后单击或拖动补白；笔径以毫米显示，笔迹按原图归一化坐标保存。黑色代表白墨覆盖；导出时为原像素 C0 M0 Y0 K100 栅格与独立透明蒙版。
6. 滚轮缩放，普通拖动平移；启用画笔时按住 **Alt 拖动**平移。“适合画布”复位，“实际尺寸”按 Windows 96 逻辑像素/英寸显示，未经显示器物理校准；“像素细节”按一个原图像素对应一个逻辑显示像素查看。
7. **Ctrl+Z** 撤销参数或画笔操作。“恢复默认设置”保留图片、项目名、备注和笔迹，且可撤销。重新导入图片清除笔迹和撤销历史。
8. 高级设置默认收起，展开状态会记住；收起不改变参数。主题跟随系统。右上角“使用教程”提供八步整窗遮罩引导，目标控件可以操作，Esc 退出；退出恢复原查看页，保留主动修改的参数。

## PDF 与 AI 导出

- 点击“导出 PDF”，选择新文件名。六页依次为组合图、白墨、主体刀线、底座与插槽、独立插脚参考、A4 横向制版说明。尺寸使用毫米，彩稿保留原像素及透明度。
- 点击“生成 .ai 文件”，选择新文件名。需要本机已安装并可使用 Illustrator；本次实测版本为 29.1.0。软件生成 CMYK 资源，再通过 COM 调用原项目 JSX，由 Illustrator 新建、嵌入并保存真正的 AI。完成后 Illustrator 会显示文件。
- AI 有两张画板和六个图层，白墨默认隐藏，制版说明默认锁定；插脚框仍独立于主体。说明中文字转轮廓，避免对方缺字体。
- PDF 彩稿采用 Windows 自带 RSWOP.icm（Agfa : Swop Standard）。Illustrator 使用其当前新建文档 ICC；本机为 Japan Color 2001 Coated，导入时可产生色彩转换。两者不能视为完全相同的彩稿数值。实际 AI ICC 保存在同名 `.windows-color.json` 中；本软件不修改 Illustrator 全局色彩设置。
- 白墨为纯 K100，保留原尺寸蒙版；本机实测经过 AI 保存、重开及再次导出后，覆盖像素仍为 K100，蒙版逐字节一致。
- 同名文件拒绝覆盖，请使用新名称。取消保存不导出。连接失败会显示警告并保留“制版数据”文件夹；在 Illustrator 的“文件 → 脚本 → 其他脚本”中运行其中的 JSX。该文件夹和目标路径含绝对引用，运行前请勿移动；警告不代表 AI 已生成。
- 没有 Illustrator 仍可导出 PDF。Windows RSWOP.icm 缺失会明确报错，不退回 RGB。含非默认旋转标记的 PNG 请先按正确方向另存，避免预览与导出方向不同。

## 本版边界

- 原像素实白/跟随透明度、阈值和补白画笔可导出。白墨内缩、自动填孔、矢量白墨仍未实现；开启不支持的选项会拒绝导出。
- 没有项目保存/恢复；关闭后参数和笔迹不能从 PDF/AI 恢复到本软件。
- 八步教程可手动重看，暂不在首次启动自动弹出。高 DPI、多显示器、长时间大图操作和干净系统仍待全面验收。
- 未签名便携包，目标 Windows x64；实测 Windows 11 build 26200，Windows 10 和 ARM64 未验证。不是工厂试切验收结论。

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

## 导出验证复现与后续工作

`electron . --export-smoke --ai-smoke` 使用真实界面计算默认图并执行生产导出链路；通过 `ACRYLIC_EXPORT_TEST_DIR` 指定一个新的空目录。增加 `--brush-fixture` 测试半透明、补白与双插脚。此命令会调用本机 Illustrator，应仅在已授权的测试中运行。

`tests/verify-ai.jsx` 在 Illustrator 中重开测试文件并检查图层、画板、尺寸及嵌入资源；随后 `python tests/audit-export.py <测试目录>` 检查 PDF 色彩空间、ICC、原像素和 AI 往返白墨蒙版。Python 检查需要 pypdf、Pillow、numpy，仅供开发验证，便携包运行不需要 Python。

后续补齐白墨填孔/内缩/矢量、相同 alpha 的 Mac/Windows 几何对照、大图与干净系统检查、工厂试切和发布签名。Windows 在独立目录维护；不覆盖 Mac 发布包。
