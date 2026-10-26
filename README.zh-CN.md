<p align="center">
  <img src="docs/images/mura-logo.png" width="112" height="112" alt="Mura logo">
</p>

# Mura — 让 AI Agent 把明天要做的事写到你的 Mac 桌面上

<p align="center">
  <a href="README.md">English</a> · <strong>中文</strong> · <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-blue.svg"></a>
</p>

**Mura 是一个只有 600 KB 的 macOS 命令行小工具。你的 Agent（Claude Code、Codex……）把你明天要做的事交给它，过了零点，桌面就会变成这张清单，画风和 Excalidraw 一样是手绘的。早上醒来看一眼屏幕，就知道今天要干什么。**

![Mura 壁纸示例：手绘风的待办清单，标题有红色手绘下划线，重要事项有黄色荧光笔，完成的打勾划掉，底部有蓝色便签](docs/images/mura-hero-zh.png)

## 为什么

待办软件要你自己去打开，桌面却一直摆在你眼前。Mura v1 是一块要你亲手写的画布；v2 专门做给 Agent 用：没有编辑器，不用算坐标，后台也不常驻任何程序。Agent 只管把文字交过来，排版和绘制都由 Mura 完成。

## 安装

需要 macOS 14 以上，并装好 Xcode 命令行工具（`xcode-select --install`）。

```bash
git clone https://github.com/risingjerry/Mura && cd Mura && script/install.sh
```

这一步会把 `mura` 装到 `~/.local/bin`，下载两款手写字体（Virgil 和小赖字体，约 22 MB），再装一个每天零点后自动切换壁纸的系统定时任务（LaunchAgent）。平时没有任何程序在后台跑。

## 在 Claude Code / Codex 里用

```bash
npx skills add risingjerry/Mura      # 或把 skills/mura 复制到 ~/.claude/skills/
```

然后正常说话就行：「明天先写完发布说明，下午两点评审设计，晚上健身，帮我放到桌面上。」做完一件事说一声：「设计评审搞定了。」

## 自己用

```bash
mura plan --date tomorrow "! 写完发布说明" "14:00 设计评审" "健身 45 分钟"
mura add "给银行打电话"            # 改今天的内容：壁纸马上更新
mura done 2                        # 勾掉第 2 件
mura render --date tomorrow        # 只生成预览图，不动壁纸
mura undo                          # 换回上一张壁纸
mura help                          # 列出所有命令（JSON 格式）
```

每一天就是 `~/Library/Application Support/Mura/days/` 里的一个 Markdown 文件：`# 标题`、`- [ ] 事项`、`- [x] 已完成`，事项前加 `!` 表示重要，`> 一句话` 会变成底部的便签。

## 画出来是什么样

- 手写体标题，下面一条红色手绘下划线，标题上方是日期。
- 每件事前面一个手绘方框。重要的事涂上黄色荧光笔，做完的打绿勾并划掉；全部做完时，标题旁会圈出「全部搞定!」。
- 字号、换行、要不要分两栏都会按每块屏幕自动调整，实在放不下就显示「…还有 N 项」。
- 每块屏幕按原生分辨率单独出图，所有桌面（Space）一起换。

## 怎么做到的

用 Swift 加 macOS 自带的 CoreText 和 CoreGraphics 绘图。手绘线条来自 [rough.js](https://github.com/rough-stuff/rough)（Excalidraw 用的就是它），直接跑在系统自带的 JavaScriptCore 里，不需要浏览器，也不需要网页视图。两块 4K 屏一起出图用不到一秒；内容没变时，`mura tick` 只要几毫秒。

macOS 的公开接口只会换掉当前这个桌面的壁纸，所以 Mura 会另外去改系统的壁纸记录，让其他桌面也一起换。改之前先备份，改完检查一遍；万一 macOS 不认，就自动还原。不想要这个功能的话，运行 `mura config set spaces current` 关掉。

## 常见问题

**我电脑的时区和我实际生活的时区不一样。** 运行 `mura config set timezone Asia/Shanghai`（任意标准时区名都行）。「今天」怎么算、零点什么时候切换，都会按这个时区来。

**会上传我的清单吗？** 不会。所有数据都在 `~/Library/Application Support/Mura` 里。唯一一次联网，是 `mura setup` 下载字体。

**怎么换回原来的壁纸？** 运行 `mura undo`（多次运行可以一步步往回退），或者去「系统设置 → 墙纸」里重新选。

**v1 那块手绘画布去哪了？** v1（带手绘编辑器的菜单栏 App）保留在 `main` 分支和 Releases 里。v2 是有意去掉了编辑器。

## 卸载

```bash
mura schedule uninstall && mura undo   # 先停掉自动切换，再换回原来的壁纸
rm ~/.local/bin/mura && rm -rf ~/Library/Application\ Support/Mura
```

## 许可证

MIT。rough.js 用的是 MIT 许可证；Virgil 和小赖字体用的是 SIL OFL 1.1 许可证，都是安装时下载，不随仓库分发。详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

---

如果 Mura 让你每天早上更清楚要做什么，点个 Star 能帮更多人找到它。
