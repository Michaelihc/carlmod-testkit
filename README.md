# Carl Mod 本地测试工具（carlmod-testkit）

[English](README.en.md)

在一台 Windows 电脑上同时运行 **Carl Mod 专用服务端**和**安卓模拟器里的真实游戏客户端**，用来测试服务器配置和服务端插件。
常用操作都有双击即可运行的 `.cmd` 文件和一个中文菜单；出错时会用中文说明原因和下一步该做什么。

> 本项目与 SCP: Secret Laboratory（Northwood Studios）及 Carl Mod 均无关联。仓库里不包含任何游戏文件，
> 服务端和客户端请从 Carl Mod 官方渠道获取。详见 [NOTICE](NOTICE)。

## 功能

- 一键准备：检查环境，解压服务端，自动下载安装 Android SDK 并创建模拟器。
- 一键开始测试：启动本地服务器 → 启动模拟器 → 安装并启动客户端 → 自动点击菜单连接服务器。
- 向服务器发送控制台命令（`forcestart`、`roundrestart`……），截图，测量客户端帧率。
- 双客户端测试（两个模拟器同时连接）。
- 可选：安装 [LabAPI-Mobile](https://github.com/Michaelihc/labapimobile) 插件框架和测试辅助插件
  TestKitHelper（显示命令输出、生成假人玩家、传送）。

原始的服务端 ZIP 和 APK 只会被读取和复制，从不修改；所有生成的文件都在 `.runtime\` 文件夹里。

## 环境要求

| 项目 | 要求 |
| --- | --- |
| 系统 | 64 位 Windows 10（1803 或更新）或 Windows 11 |
| 虚拟化 | 已启用“Windows 虚拟机监控程序平台”（Windows Hypervisor Platform，WHPX），BIOS 中已开启 CPU 虚拟化 |
| Java | 17 或更新版本（只在安装 Android SDK 时需要），例如 [Temurin](https://adoptium.net) |
| Python | 3.8 或更新版本（只在解压服务端 ZIP 时需要），[python.org](https://www.python.org)，安装时勾选 “Add python.exe to PATH” |
| 内存 | 16 GB 以上；双客户端建议 32 GB（每个模拟器占 6 GB） |
| CPU | 8 线程以上（模拟器配置为 8 核） |
| 磁盘 | 本工具所在盘约 5 GB；Android SDK 和模拟器所在盘约 20 GB，每多一个模拟器再加约 10 GB |
| 网络 | 第一次安装 Android SDK 需要下载约 2 GB（dl.google.com） |
| .NET SDK | 可选，只在从源码构建辅助插件时需要 |

启用 WHPX：开始菜单搜索“启用或关闭 Windows 功能”，勾选 **Windows 虚拟机监控程序平台**，确定后重启电脑。
已经开启 Hyper-V 的电脑通常不需要再做什么，`check.cmd` 会告诉你结果。本工具不会修改任何 Windows 功能。

> 用户名或路径里有中文时，Android 模拟器可能无法启动。建议把本工具放在英文路径下（如 `D:\carlmod-testkit`）；
> 如果 Windows 用户名是中文，见下方“配置”中的 `AndroidSdk` 和环境变量 `ANDROID_AVD_HOME`。

## 准备游戏文件

把下面两个文件放进 `inputs` 文件夹（每种一个，文件名随意）：

1. Carl Mod **Windows 服务端** ZIP（压缩包里有 `Carl Mod.exe`）；
2. Carl Mod **安卓客户端** APK（`.apk`，或 `.apk.1` 这类扩展名也可以）。

请从 Carl Mod 官方渠道获取，本项目不提供下载。文件放在别处，或已经有解压好的服务端文件夹时，
可以在配置文件里指定路径（见“配置”）。

## 第一次使用

1. 下载本工具（`git clone`，或在 GitHub 页面点 Code → Download ZIP 后解压）。
2. 把服务端 ZIP 和 APK 放进 `inputs` 文件夹。
3. 双击 **`check.cmd`** 检查环境，按每个 `[失败]` 项的“下一步”处理，直到全部通过。
4. 双击 **`setup.cmd`**：解压服务端、下载 Android SDK、创建模拟器 `carlmod_api36`。第一次需要 10～20 分钟。
5. 双击 **`start-all.cmd`**：
   - 第一次启动服务器时会先启动一次生成配置文件，再正式启动（共约 1.5 分钟）；
   - 模拟器冷启动约 1 分钟；
   - 第一次会把游戏安装进模拟器（约 30 秒）；
   - 然后自动启动游戏、进入“游戏 → IP直连”，连接 `10.0.2.2:7777`，等到进入游戏场景。
6. 开始回合：双击 `send-command.cmd`，输入 `forcestart` 回车（或在菜单里选 4）。
7. 测试结束后双击 **`stop-all.cmd`**，关闭本工具启动的模拟器和服务器。

也可以只用菜单：双击 **`menu.cmd`**，按编号操作。

## 日常使用

| 双击 | 作用 |
| --- | --- |
| `menu.cmd` | 中文菜单，包含下面所有操作和更多选项 |
| `check.cmd` | 检查环境 |
| `setup.cmd` | 一键准备（可重复运行，已完成的步骤会跳过） |
| `start-all.cmd` | 一键开始测试（已在运行的服务器和模拟器会直接复用） |
| `send-command.cmd` | 逐条输入服务器控制台命令，空行退出 |
| `screenshot.cmd` | 模拟器截图并打开 |
| `stop-all.cmd` | 全部停止 |

所有功能都在 `scripts\` 里，也可以在 PowerShell 中直接运行（参数见各脚本开头的说明，
`Get-Help .\scripts\Start-All.ps1 -Detailed` 可查看）：

```powershell
.\scripts\Start-All.ps1 -ForceStart            # 一键开始并开始回合
.\scripts\Send-ServerCommand.ps1 forcestart     # 开始回合
.\scripts\Send-ServerCommand.ps1 roundrestart   # 回到大厅
.\scripts\Capture.ps1 -Name 出生点               # 截图到 .runtime\captures\
.\scripts\Start-Client.ps1 -Restart; .\scripts\Connect-Client.ps1   # 重启游戏并重新连接
.\scripts\Show-Status.ps1                       # 查看状态
.\scripts\Stop-All.ps1                          # 全部停止
```

PowerShell 提示“禁止运行脚本”时，用 `.cmd` 文件，或这样运行：
`powershell -ExecutionPolicy Bypass -File .\scripts\Start-All.ps1`。

### 服务器控制台命令

服务器不读取键盘输入，本工具通过“文件控制台”发送命令：

- 控制台命令直接输入：`forcestart`（开始回合）、`roundrestart`（回到大厅）。
- 远程管理（RA）命令前面加 `/`：`/roundlock enable`、`/forceclass 2 Scp173`。
- 文件控制台**不返回命令的文字输出**。脚本会显示发送命令后服务器日志里新增的内容；安装辅助插件 TestKitHelper
  后，控制台输出也会写进日志，这样就能看到命令结果。RA 命令会执行，但它们的回复不会出现在服务器控制台里，
  请在客户端上或用 `testkit list` 查看效果。
- 每条命令服务器都会记一条 `Error in server console: Error while sending message.`，这是正常现象，命令照样执行。

### 在游戏里使用 RA 命令

模拟器里点“管理”打开的远程管理面板可能无法使用。请改用游戏内的 **控制台**：输入以 `/` 开头的 RA 命令
（如 `/forceclass 2 Scp173`），点 PROCEED。前提是这个客户端有 RA 权限，用下面的命令授予（客户端需要已连接过服务器）：

```powershell
.\scripts\Grant-RemoteAdmin.ps1 -Restart
```

它从服务器日志读取客户端的设备 ID（形如 `device_xxxx@device`），写进测试服务器的 `config_remoteadmin.txt`
（权限组 owner），然后重启服务器；客户端会自动重新连接。每个模拟器（AVD）的设备 ID 不同，第二个客户端连上后
再运行一次即可。

### 截图和帧率

- 截图：`screenshot.cmd`，或 `.\scripts\Capture.ps1 -Name <标签>`，保存为 `.runtime\captures\<时间>-<标签>.png`（2400×1080）。
- 帧率：`.\scripts\Measure-FrameTime.ps1 -Name <标签> -DurationSec 30`，输出平均 FPS、平均帧时间、P50/P95/P99 帧间隔
  和超过 33.4 ms 的比例，并保存为 `.runtime\captures\frametime-<标签>-<时间>.json`。

客户端在模拟器里经过 ARM 指令转译运行，帧率不等于手机上的帧率，只适合比较不同版本或配置：使用同一个模拟器、
同一分辨率和同一场景（例如 `forcestart` 后站在 D 级人员出生房间不动）；每种配置至少测 3 次、每次 30 秒，
交替测量（A、B、A）后比较平均值，单次之间相差约 ±4 FPS 属于正常。屏幕刷新率为 60 Hz，帧间隔集中在 16.7、33.3、50 ms 附近。

### 双客户端

需要两名玩家的测试（观战、铐人、SCP 攻击玩家……）要用第二个模拟器。一个 AVD 同时只能运行一次，所以第二个客户端
使用自己的 AVD `carlmod_api36_b` 和序列号 `emulator-5556`：

```powershell
.\scripts\Install-AndroidSdk.ps1 -Second      # 只需一次：创建第二个模拟器（或 setup.cmd 之后在菜单选 10）
.\scripts\Start-All.ps1 -Second               # 两个客户端一起启动并连接
.\scripts\Start-All.ps1 -SecondOnly           # 只启动并连接第二个客户端
.\scripts\Capture.ps1 -Second -Name b-view    # 其它脚本加 -Second 即作用于第二个模拟器
```

两个模拟器加服务器需要较多内存（建议 32 GB）。每个 AVD 有自己的设备 ID，所以两个客户端是不同的玩家。
玩家 ID 按加入顺序分配，每次重连都会变化，操作某个玩家前先用 `testkit list`（辅助插件）或服务器日志里的
`Joined` 行确认。有两名玩家时大厅倒计时结束会自动开始回合；`/roundlock enable` 可以让一方死亡后回合继续。

## 配置

不需要配置也能用。要修改时，把 `testkit.config.example.psd1` 复制为 `testkit.config.psd1`，只保留要改的项：

| 键 | 默认值 | 说明 |
| --- | --- | --- |
| `Port` | `7777` | 测试服务器 UDP 端口；模拟器连接 `10.0.2.2:<端口>` |
| `ServerZip` | inputs 里唯一的 `*.zip` | 服务端 ZIP |
| `ServerFolder` | 空 | 已解压的服务端文件夹（含 `Carl Mod.exe`），设置后不需要 ZIP 和 Python；只复制，不修改 |
| `Apk` | inputs 里唯一的 APK | 客户端 APK |
| `AndroidSdk` | `%LOCALAPPDATA%\Android\Sdk` | Android SDK 位置（也读取 `ANDROID_SDK_ROOT` / `ANDROID_HOME`） |
| `AvdName` / `Serial` | `carlmod_api36` / `emulator-5554` | 第一个模拟器 |
| `SecondAvdName` / `SecondSerial` | `carlmod_api36_b` / `emulator-5556` | 第二个模拟器 |
| `CommandSession` | `testkit` | 文件控制台会话名（服务器以 `-keytestkit` 启动） |
| `ConfigOverrides` | `@{ afk_time = '0' }` | 每次启动前写入 `config_gameplay.txt` 的配置 |

模拟器（AVD）默认放在 `%USERPROFILE%\.android\avd`，可以用环境变量 `ANDROID_AVD_HOME` 改到别的盘。

## 文件位置

| 位置 | 内容 |
| --- | --- |
| `inputs\` | 你放进来的服务端 ZIP 和 APK（Git 忽略） |
| `.runtime\server-original\` | 解压出的原始服务端（只读使用，从不运行） |
| `.runtime\server-<端口>\` | 测试服务器（从原始服务端复制）；配置、封禁、日志在其中的 `AppData\` |
| `.runtime\apk\` | APK 副本（adb 只接受 `.apk` 扩展名） |
| `.runtime\logs\` | 服务器日志 `server-<端口>-<时间>.log`、模拟器日志 `emulator-<端口>.log` |
| `.runtime\captures\` | 截图和帧率结果 |
| `.runtime\state\` | 本工具启动的服务器和模拟器记录（用于安全地停止它们） |
| `%LOCALAPPDATA%\Android\Sdk`、`%USERPROFILE%\.android\avd` | Android SDK 和模拟器 |

`.runtime\` 可以随时整个删除（先运行 `stop-all.cmd`），下次使用时会重新生成。

## 安全措施

- 服务端 ZIP、原始服务端文件夹和 APK 只读取和复制，从不修改；测试服务器总是单独的一份副本。
- 启动前写入 `hoster_policy.txt`（`gamedir_for_configs: true`），服务器的配置、封禁列表和日志都放在
  `.runtime\server-<端口>\AppData\`，不写进你电脑上真正的 `%APPDATA%\SCP Secret Laboratory`。
  **唯一的例外**是服务器的 player-prefs 文件 `%APPDATA%\SCP Secret Laboratory\registry.txt`：服务器在读取上述设置之前
  就确定了它的位置，每次回合重启会更新其中的 `LastRoundrestartTime` 和 `SrvSp_*` 键。除此之外不会写入那里。
- 端口已被占用时拒绝启动服务器；同一端口已有本工具的服务器在运行时直接复用。
- 停止服务器只按记录的 PID 进行，并先核对进程名是 `Carl Mod.exe`、命令行包含对应端口；从不按进程名批量结束进程。
- 关闭模拟器只对指定序列号发送 `adb emu kill`；“全部停止”只处理本工具启动的模拟器和服务器。
- 不修改 Windows 功能、防火墙或系统设置。唯一对系统进程的操作是对本工具启动的模拟器的 qemu 进程关闭 Windows
  节能限速（见“常见问题”）。

## 可选：LabAPI-Mobile 和测试辅助插件

[LabAPI-Mobile](https://github.com/Michaelihc/labapimobile) 是移植到 Carl Mod 服务端的 LabAPI 插件框架。
安装到测试服务器（需要先停止该服务器，会从 GitHub 下载最新发布版）：

```powershell
.\scripts\Stop-TestServer.ps1
.\scripts\Install-LabApiMobile.ps1             # 无网络时：-Zip <下载好的 LabApiMobile-*.zip>
```

插件 DLL 放进 `.runtime\server-<端口>\AppData\SCP Secret Laboratory\LabAPI-Mobile\plugins\global\`，重启服务器后加载。

**测试辅助插件 TestKitHelper**（源码在 [`plugin/TestKitHelper`](plugin/TestKitHelper)）：

```powershell
.\scripts\Install-HelperPlugin.ps1              # 有 .NET SDK 时从源码构建，否则下载发布页上的预编译 DLL
```

| 命令（控制台直接输入；游戏内控制台加 `/`） | 作用 |
| --- | --- |
| `testkit list` | 列出玩家：ID、昵称、角色、坐标、是否假人 |
| `testkit dummy <角色> [<玩家ID> \| <x> <y> <z>]` | 生成假人玩家：在角色出生点、指定玩家面前 1.5 米处（面向该玩家），或指定坐标 |
| `testkit remove <玩家ID> \| all` | 移除一个或全部假人 |
| `testkit tp <玩家ID> <目标玩家ID> \| <x> <y> <z>` | 把玩家传送到另一个玩家处或指定坐标 |

角色名如 `ClassD`、`Scientist`、`FacilityGuard`、`NtfPrivate`、`ChaosRifleman`、`Scp173`、`Scp049`，也可以用数字。
假人在服务器上运行，不需要第二台手机或模拟器；回合重启时自动移除。生成假人时服务器日志会出现几行
`The referenced script on this Behaviour ... is missing!` 和 `Error during IP passthrough processing`，不影响使用。
插件同时会把服务器控制台的输出写进服务器日志（每行以 `[console]` 开头），`Send-ServerCommand.ps1` 因此能显示命令结果。
`testkit` 命令不检查权限，只应安装在本地测试服务器上。

## 操作客户端界面

`Connect-Client.ps1` 会自动完成连接。需要手动操作时，可以用 adb 点击（2400×1080 横屏坐标）：

| 位置 | 点击坐标 (x, y) |
| --- | --- |
| 主菜单“游戏”标签 | 298, 50 |
| “游戏”标签中的“IP直连” | 395, 348 |
| IP直连弹窗的地址输入框 | 1200, 526 |
| IP直连弹窗的“连接” | 1063, 593 |
| 游戏内摇杆中心（滑动行走） | 358, 748 |
| 游戏内 E（交互） | 2118, 596 |
| 游戏内“控制台” | 2333, 793 |
| 控制台输入框 / PROCEED | 1074, 919 / 1862, 918 |

```powershell
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb -s emulator-5554 shell input tap 2118 596                 # 按 E
& $adb -s emulator-5554 shell input swipe 358 748 358 480 4000   # 向前走 4 秒
& $adb -s emulator-5554 shell input swipe 1300 300 1300 560 600  # 在屏幕右半边拖动：转视角（这里是向下看）
& $adb -s emulator-5554 shell input text "/forceclass%s2%sScp173" # 输入文字（%s 表示空格）
& $adb -s emulator-5554 logcat -s Unity:V                         # 查看客户端日志
```

主菜单标签从左到右：开始、游戏、设置、操作指南、Console、退出。游戏内按钮：菜单、控制台、玩家列表、管理。
SCP 的大攻击按钮在 1728, 786。部分操作在模拟器的触屏界面上做不到：铐人、SCP-939 的蓄力扑击、SCP-106 的猎手地图
（小地图显示为空）和 SCP-079 的区域断电。

## 常见问题

**游戏一启动就闪退（日志里有 SIGILL）**
必须使用 API 36（Android 16）的 x86_64 系统镜像，`setup.cmd` 默认就是它。API 34 镜像的 ARM 转译器不支持游戏加载时执行的
AArch64 `SEVL` 指令，客户端会崩溃。

**模拟器窗口不在前台时游戏明显变慢**
Windows 会对后台窗口的进程做节能限速（EcoQoS），游戏帧率会下降约四分之一。`Start-Emulator.ps1` 会对它启动的模拟器关闭
这项限速，`Measure-FrameTime.ps1` 每次测量前也会再做一次。模拟器不是用本工具启动的话，再运行一次
`Start-Emulator.ps1`（模拟器已在运行时，它只应用测试设置并关闭节能限速，不会重启模拟器）。

**一个人站着不动约 90 秒被踢出**
这是服务器的挂机踢出。本工具默认在 `config_gameplay.txt` 中设置 `afk_time: 0` 关闭它；可在配置的 `ConfigOverrides` 中修改。

**发送命令后看不到输出**
文件控制台不返回文字。看服务器日志（`.runtime\logs\`），或安装辅助插件 TestKitHelper 后再发命令。RA 命令（`/` 开头）
的回复不会出现在服务器控制台，请在游戏里确认效果。

**点“管理”打不开远程管理面板**
用游戏内“控制台”输入 `/` 开头的 RA 命令，并先用 `Grant-RemoteAdmin.ps1 -Restart` 给这个客户端授权（见上文）。

**提示端口被占用**
另一个程序（可能是另一个服务端）占用了这个 UDP 端口。关掉它，或在 `testkit.config.psd1` 中把 `Port` 改成别的值（如 7778）。
本工具不会去结束占用端口的程序。

**连上后是黑屏，只有观战按钮**
回合进行中加入的玩家会成为观察者。发送 `roundrestart`，等客户端回到大厅后再发 `forcestart`。

**自动连接失败 / 一直停在主菜单**
用 `screenshot.cmd` 看看客户端当前画面。新建的模拟器第一次全屏时会弹出“全屏查看”提示挡住点击，`Start-Emulator.ps1`
会预先关闭它；如果是手动启动的模拟器，先运行一次 `Start-Emulator.ps1`。自动点击按横屏比例计算，适用于 2400×1080
及同宽高比的屏幕。然后在菜单选 9（重新连接客户端）。

**模拟器启动失败**
查看 `.runtime\logs\emulator-<端口>.log` 和 `.log.err`。常见原因：WHPX 未启用（运行 `check.cmd`）、磁盘空间不足、
路径含中文、显卡驱动过旧。

**服务端更新了**
把新的 ZIP 放进 `inputs`（删掉旧的），运行 `.\scripts\Import-Server.ps1 -Force`。已有的测试服务器 `.runtime\server-<端口>\`
仍是旧版本：停止服务器后删除该文件夹，下次启动会重新复制（其中的配置、插件和 RA 授权也会一起删除）。

**换新版本 APK / 清除游戏数据**
`.\scripts\Install-Client.ps1 -Apk <新 APK>`；`-Reinstall` 会先卸载（清除游戏数据）再安装。

## 许可证

本工具的脚本和插件源码使用 [MIT 许可证](LICENSE)。
