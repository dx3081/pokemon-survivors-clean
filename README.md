# 口袋妖怪幸存者 · Pokemon Survivors

基于 [PokéRogue](https://github.com/pagefaultgames/pokerogue) 制作的宝可梦同人幸存者游戏，免费分享 Windows 和 macOS 最终版。

俯视角自动战斗，你负责走位、抓宠和养成。支持中文 / English。

## 下载最终版

- [Windows 下载](https://github.com/dx3081/pokemon-survivors-clean/releases/download/v1.0.0/PokemonSurvivors-Windows.zip)：解压后运行 `PokemonSurvivors.exe`，EXE 和 PCK 保持在同一目录。
- [macOS 下载](https://github.com/dx3081/pokemon-survivors-clean/releases/download/v1.0.0/PokemonSurvivors-macOS.zip)：解压后打开 `Pokemon Survivors.app`。
- [查看 Release 页面](https://github.com/dx3081/pokemon-survivors-clean/releases/latest)。

## 从源码运行

使用 Godot 4.7.2 打开 `project.godot`，等待资源导入后运行 `main.tscn`。项目包含 Windows Desktop 和 macOS 导出预设；导出时需安装对应版本的 Godot 导出模板。

WASD / 方向键移动；招式自动释放；Esc / Q / E 打开抓宠界面；数字键 1–5 选择精灵球。

## 来源与许可

本项目将 PokéRogue 的代码、数据和表现移植、改编为 Godot 下的即时幸存者玩法。2026-10-27 整理为公开发布版本，移除了开发工作台资料及 AI 试玩入口。

代码及受其许可覆盖的衍生部分按 **GNU AGPL v3** 发布，详见 [LICENSE](LICENSE)。

本作为非官方同人作品，与 Pokémon 官方无隶属关系。Pokémon 相关名称、图片、音乐、音效及其他第三方素材的权利归各自权利人所有，代码许可不授予额外的素材或商标权利。感谢 PokéRogue 及原素材作者，详见 [CREDITS.md](CREDITS.md)。