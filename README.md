<p align="center"><img src="assets/AppIcon-source.png" width="112" alt="亚克力立牌助手图标"></p>
<h1 align="center">亚克力立牌助手</h1>
<p align="center">从透明 PNG 到立牌制作文件，支持 macOS 与 Windows。</p>
<p align="center"><a href="https://github.com/NEKOSAIKO/acrylic-standee-helper/releases/download/windows-v0.1.1-preview.1/AcrylicStandee-0.1.1-preview.1-Windows-x64.zip"><b>⬇ Windows 预览版</b></a> · <a href="https://github.com/NEKOSAIKO/acrylic-standee-helper/releases/download/v0.2.7/AcrylicStandee-0.2.7-Mac.zip"><b>⬇ Mac 0.2.7</b></a> · <a href="https://github.com/NEKOSAIKO/acrylic-standee-helper/issues">反馈问题</a></p>

![应用预览](docs/images/app.png)

## 下载与使用

| 平台 | 下载 | 系统要求与说明 |
| --- | --- | --- |
| Windows 0.1.1 预览版 | [下载 ZIP](https://github.com/NEKOSAIKO/acrylic-standee-helper/releases/download/windows-v0.1.1-preview.1/AcrylicStandee-0.1.1-preview.1-Windows-x64.zip) · [发布记录](https://github.com/NEKOSAIKO/acrylic-standee-helper/releases/tag/windows-v0.1.1-preview.1) | x64；实测 Windows 11。Windows 10、ARM64 未验证 |
| Mac 0.2.7 | [下载 ZIP](https://github.com/NEKOSAIKO/acrylic-standee-helper/releases/download/v0.2.7/AcrylicStandee-0.2.7-Mac.zip) · [发布记录](https://github.com/NEKOSAIKO/acrylic-standee-helper/releases/tag/v0.2.7) | Apple Silicon（M 系列），macOS 14 或更新；不提供 Intel 版 |

**Windows：**完整解压 ZIP，双击“亚克力立牌助手.exe”；请保留同目录的资源文件，不要单独移动 EXE。无需安装 Node 或 Python。[Windows 使用说明](windows/README.md) · [验证记录](windows/VALIDATION.md)。

**Mac：**解压，将“亚克力立牌助手 0.2.app”拖入“应用程序”，双击打开。[Mac 使用说明](docs/使用说明.md)。

两端均可打开透明 PNG、调整刀线/白墨/底座，并点击 **生成 .ai 文件** 或 **导出 PDF**。生成 AI 需要本机 Adobe Illustrator，PDF 导出无需 Illustrator。GitHub 自动附带的 Source code 是源码，不是可运行应用。

Windows 是预览版：已验证六页 CMYK PDF、原生 AI、原像素 K100 与补白；白墨内缩、填孔和矢量输出尚未完成。PDF 采用 Windows SWOP ICC，AI 使用 Illustrator 当前文档 ICC，二者彩稿数值可能不同。详情见验证记录。

Windows 包未做发布者代码签名；Mac 包采用本地签名，尚未经过 Apple 开发者签名和公证，首次打开可能被系统提示拦截。

## 能做什么

| 功能 | 用途 |
| --- | --- |
| 主体刀线 | 调整尺寸、透明边和平滑，处理深凹口跨接 |
| 原像素白墨 | 自动生成白墨，可用画笔点击或拖动补白 |
| 独立插脚参考 | 空心蓝框标记插脚位置，交由工厂调整；底座保留插槽 |
| 分层制作文件 | 生成毫米单位的 `.ai` 文件，或六页 PDF |
| 高亮操作引导 | 界面变暗，逐步高亮当前按钮并显示教程卡片 |
| 简洁参数 | 常用选项直接可见，精细参数在“高级设置”中展开 |
| 系统外观 | 自动跟随系统浅色与深色模式 |

补白笔迹目前属于当前图片会话，关闭前请导出结果。软件生成的轮廓仍需结合工厂设备、材料和试切确认。

## 更新应用

每个版本都有独立的 Release、更新记录和下载包。关注本仓库的 Releases 即可获取更新通知；上方下载表分别指向两端当前提供的版本；Windows 预览版单独标记，不替换 Mac 稳定版。应用内暂不自动更新。

- [Mac 使用说明](docs/使用说明.md)
- [Mac 更新记录](CHANGELOG.md)
- [开发、拉取更新与发布新版](docs/开发与发布.md)

## 获取源码

```sh
git clone https://github.com/NEKOSAIKO/acrylic-standee-helper.git
cd acrylic-standee-helper
# macOS
zsh scripts/build-app.sh
# Windows 构建步骤见 windows/README.md
```

Mac 构建需要 Xcode Command Line Tools（Swift、Clang、macOS SDK）和 Python 3。编译结果在 `dist/`。已有本地仓库可使用 `git pull --ff-only` 获取更新，也欢迎通过 Issue 和 Pull Request 交流改进。

Clipper2 的许可证保留在 [vendor/Clipper2/LICENSE](vendor/Clipper2/LICENSE)。

Windows 源码在 `windows/`，复用原几何算法、Clipper2 和 Illustrator JSX；构建与验收命令见 [Windows 开发说明](windows/README.md#开发与复现)。
