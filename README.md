<p align="center"><img src="assets/AppIcon-source.png" width="112" alt="亚克力立牌助手图标"></p>
<h1 align="center">亚克力立牌助手</h1>
<p align="center">从透明 PNG 到立牌制作文件，一款原生 Mac 小工具。</p>
<p align="center"><a href="https://github.com/NEKOSAIKO/acrylic-standee-helper/releases/latest"><b>⬇ 下载最新版 Mac 应用</b></a> · <a href="docs/使用说明.md">使用教程</a> · <a href="https://github.com/NEKOSAIKO/acrylic-standee-helper/issues">反馈问题</a></p>

![应用预览](docs/images/app.png)

## 下载与使用

1. 点击上方 **下载最新版 Mac 应用**，在 Releases 的 Assets 中下载 `AcrylicStandee-*-Mac.zip`。GitHub 自动附带的 Source code 是源码，不是安装包。
2. 解压，将“亚克力立牌助手 0.2.app”拖入“应用程序”，双击打开。
3. 打开透明 PNG，调整尺寸，检查刀线、白墨与底座，再点击 **生成 .ai 文件** 或 **导出 PDF**。

**运行要求：Apple Silicon（M 系列）Mac，macOS 14 或更新版本。** 生成 `.ai` 文件需要本机安装 Adobe Illustrator；PDF 导出无需 Illustrator。暂不提供 Intel Mac 或 Windows 版本。

当前安装包采用本地签名，尚未经过 Apple 开发者签名和公证，首次打开可能被 macOS 提示拦截。

## 能做什么

| 功能 | 用途 |
| --- | --- |
| 主体刀线 | 调整尺寸、透明边和平滑，处理深凹口跨接 |
| 原像素白墨 | 自动生成白墨，可用画笔点击或拖动补白 |
| 独立插脚参考 | 空心蓝框标记插脚位置，交由工厂调整；底座保留插槽 |
| 分层制作文件 | 生成毫米单位的 `.ai` 文件，或六页 PDF |
| 高亮操作引导 | 界面变暗，逐步高亮当前按钮并显示教程卡片 |
| 简洁参数 | 常用选项直接可见，精细参数在“高级设置”中展开 |
| 系统外观 | 自动跟随 macOS 浅色与深色模式 |

补白笔迹目前属于当前图片会话，关闭前请导出结果。软件生成的轮廓仍需结合工厂设备、材料和试切确认。

## 更新应用

每个版本都有独立的 Release、更新记录和下载包。关注本仓库的 Releases 即可获取更新通知；使用上方固定入口始终进入最新版本。应用内暂不自动更新。

- [完整使用说明](docs/使用说明.md)
- [更新记录](CHANGELOG.md)
- [开发、拉取更新与发布新版](docs/开发与发布.md)

## 获取源码

```sh
git clone https://github.com/NEKOSAIKO/acrylic-standee-helper.git
cd acrylic-standee-helper
zsh scripts/build-app.sh
```

需要 Xcode Command Line Tools（Swift、Clang、macOS SDK）和 Python 3。编译结果在 `dist/`。已有本地仓库可使用 `git pull --ff-only` 获取更新，也欢迎通过 Issue 和 Pull Request 交流改进。

Clipper2 的许可证保留在 [vendor/Clipper2/LICENSE](vendor/Clipper2/LICENSE)。
