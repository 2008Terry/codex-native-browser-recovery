# Codex Native Browser Recovery

**Community diagnostic and reversible workaround. Not an OpenAI product or official signed fix.**

Windows 原生 Computer Use 网页识别问题的本地检测与可回滚修复工具。版本：`0.1.0-preview`。

默认操作仅检查组件文件。只有一个完整 SHA-256 匹配的已验证组件可以修复；未知版本会拒绝修改。文件检测结果不能证明网页操作一定失败或成功。

## 下载

- [预发布版 v0.1.0-preview](https://github.com/2008Terry/codex-native-browser-recovery/releases/tag/v0.1.0-preview)
- [直接下载 ZIP](https://github.com/2008Terry/codex-native-browser-recovery/releases/download/v0.1.0-preview/CodexNativeBrowserRecovery-0.1.0-preview.zip)
- [ZIP 的 SHA-256 校验值](https://github.com/2008Terry/codex-native-browser-recovery/releases/download/v0.1.0-preview/CodexNativeBrowserRecovery-0.1.0-preview.zip.sha256.txt)

请下载这个带有工具名称的 ZIP；GitHub 自动生成的 Source code 压缩包面向源码查看与构建。

## 适用问题

原生 Computer Use 能找到 Chrome/Edge 窗口，但读取页面时停止，并报：

> could not determine the current browser URL on Windows

已知缺陷会把中文“文档”或其他本地化 UIA 类型名称与固定英文 `document` 比较。修复改用成功读取的数字 Document 类型 `50030`。相同报错也可能有其他原因。

具体数据流是：读取 `CachedLocalizedControlType`，保留非空的本地化名称，再以固定 ASCII `document` 筛选网址候选。类型名称不匹配会在后续 `RootWebArea` 和网址值检查之前排除网页文档。本工具只替换该文档类型谓词，仍要求数字类型读取成功且值为 `50030`。

## 快速使用

1. 解压整个 ZIP 到普通本地文件夹，先读本说明。需要 Windows 内置的 64 位 Windows PowerShell 5.1，或 64 位 PowerShell 7；无需 Python、Node、浏览器扩展或额外安装。
2. 保持 Codex 正常运行，双击 `01-check.cmd`。查看实际运行路径、完整文件哈希、已知/未知状态，以及备份是否可用。
3. 只有检测到匹配的 `KnownOriginal` 且 Windows 原签名为 `Valid`，才考虑修复。保存工作并完全退出 Codex，再双击 `02-repair.cmd`，选择 `Y` 明确接受签名失效。
4. 正常打开 Codex，使用 [原生验收提示](NATIVE-ACCEPTANCE.txt) 验证实际读取、输入、点击、跳转。浏览器扩展测试不能替代原生验收。
5. 需要撤销时，保存工作并完全退出 Codex，双击 `03-restore.cmd`，选择 `Y`。这会恢复旧官方原版，旧故障可能重现。

下载文件若被 Windows 或组织脚本策略阻止，请先审阅源码和校验值，按所在环境的规则由本人或 IT 授权；工具不会调整执行策略或自动提权。

## 看懂检测结果

| 结果 | 意义与下一步 |
|---|---|
| `KnownOriginal` | 找到已知存在本地化缺陷的完整文件；当前用户是否实际受影响仍需原生测试。有效原签名是应用修复的必要条件。 |
| `KnownPatched` | 文件与本次验证的修正版完全一致；单独检查其原版备份是否有效。它不是新的网页验收记录。 |
| `Unknown` | 文件不在白名单，可能是官方新版本，也可能有其他变化；拒绝旧补丁。 |
| `OnlyCachedRuntime` | 只找到一个缓存，但没有确认应用实际加载它。 |
| `Ambiguous` | 多个组件且目标不明确；不会按目录时间选旧缓存。 |
| `InspectionUnavailable` | 无法读取进程路径；不会把访问失败解释成没有进程。 |

常用退出码：0 为已知修复文件的检查通过或请求的文件操作完成；10 为已知原版；20 为未知文件；21 为仅缓存；22 未找到；23 多目标；24 进程检查不可用；25 活跃路径不识别；26 另有未知缓存；27 修复文件缺少可用原版备份；28 原签名无法验证；29 清单读取不完整；30 操作拒绝/失败；31 报告写入失败。请同时读状态与说明。

## 修复范围

当前只支持以下一个 `@oai/sky 0.7.13` 文件对，**同版本号不代表同文件**：

```text
Original SHA256
11825CB78575D9099AED8F13D16F78B03C20A1A0EBC809CF78B406FB2F25F5F8

Patched SHA256
C94B17C278AEA46D1DFD42422AF326C7D99B8C604B449695410FFF88B3135B43
```

修改位于 `0x1B6C6` 的 42 字节区域，其中 36 字节变化。后续 RootWebArea、网址及访问检查保留。补丁不会适配未知哈希，不会通过搜索相同指令就向新版本应用。

这是直接修改原生组件的社区方案，会让原 OpenAI 数字签名失效。更新可能覆盖或切换组件，重启后也应检查实际运行文件。范围与局限见 [审查和验证说明](docs/REVIEW.md)。

## 签名影响

失效的是运行组件 `codex-computer-use.exe` 的 Authenticode 签名：修复后预期显示 `HashMismatch`。本工具脚本也没有发布者数字签名，不能视作官方发行版。依赖有效签名的 Windows 或组织策略可能拒绝加载修改后的组件；工具不会改变这些策略。恢复操作应得到已验证的原版完整哈希及 `Valid` 签名。请先理解并明确接受这一影响，再选择应用修复。

## 备份与报告

- 首次修复前，从使用者本机已验证的官方原文件生成完整备份；ZIP 中没有 OpenAI 可执行文件。
- 默认备份：`%LOCALAPPDATA%\CodexNativeBrowserRecovery\backups\<Original SHA256>.exe`。
- 默认报告：`%LOCALAPPDATA%\CodexNativeBrowserRecovery\reports\last-report.json` 及 `.txt`。
- 报告包含时间、系统 UI 语言、组件哈希、版本、签名和运行路径；保存时替换用户配置目录前缀。没有网页内容、浏览历史、账号或原始对话；发布报告前仍请自行检查内容。
- 工具不上传报告、不注册后台任务、不改全局 Codex 规则、不结束应用或组件进程。Windows 签名校验使用系统信任服务。
- 文件修改使用独占句柄、完整镜像哈希及读回验证。写入失败会尝试恢复原字节；若写入和恢复均失败，会明确报错并要求保留备份、停止使用该文件。

## 命令行

```powershell
.\ComputerUse.ps1 -Action Check -Json
.\ComputerUse.ps1 -Action Repair -AcceptSignatureChange
.\ComputerUse.ps1 -Action Restore -ConfirmRestore
```

多个缓存时，审查清单后可明确给出 `-HelperPath '...\codex-computer-use.exe'`；该路径仍须在标准当前用户运行清单中，完整文件白名单照常适用。显式选择缓存不代表它正在使用。

已由其他工具修复、且已有完整官方原版备份的使用者，可用 `-BackupPath '...\original.exe'` 指定原备份；每次仍校验其完整哈希和有效签名。缺少备份时不会下载其他人的程序替换。

`-ReportDirectory '...'` 可指定报告目录。报告只保留最近一次结果；脚本根本未启动或报告无法写入时，不要把旧报告当作本次结果。

## 测试与构建

```powershell
.\tests\Test-Recovery.ps1
# 可选：用自己电脑上的已验证原始文件执行真实字节的副本测试
.\tests\Test-Recovery.ps1 -OriginalHelper '...\original.exe'
.\build.ps1
```

普通测试无外部依赖。真实字节测试只在本地未执行的副本上进行；不提供原始文件时会明确跳过，不会虚报通过。构建只收录明确列出的源码、文档、许可证和验证记录，生成 ZIP 与 SHA256；不会包含运行报告、个人备份、测试副本。

## 来源

- [本地化类型缺陷分析 #53026](https://github.com/openai/codex/issues/53026)
- [韩文环境的运行时及前后对照 #54458](https://github.com/openai/codex/issues/54458)
- [中文环境的 Chrome/Edge 恢复报告 #54532](https://github.com/openai/codex/issues/54532)
- [社区原始修复代码的固定提交](https://github.com/heelee912/codex/tree/95ee61db4a387944889edc9a5b6e97272c8fca9d/tools/windows-cua-document-fix)

采用 Apache-2.0 许可证，保留上游来源和署名，见 LICENSE 和 NOTICE。本项目中的新增 PowerShell 实现与通用交付逻辑也使用该许可证；对 OpenAI 自身程序不授予任何额外权利。
