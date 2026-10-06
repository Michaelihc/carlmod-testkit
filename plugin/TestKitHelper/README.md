# TestKitHelper

Carl Mod 本地测试辅助插件（[LabAPI-Mobile](https://github.com/Michaelihc/labapimobile) 插件）。只用于本地测试服务器：
`testkit` 命令不检查权限。

## 功能

- **控制台镜像**：把服务器控制台的每行输出写进服务器的 Unity 日志（`-logFile`），每行以 `[console] ` 开头。
  文件控制台不返回命令的文字，有了它 `scripts\Send-ServerCommand.ps1` 就能显示命令结果。
- **假人玩家**：在服务器上生成不需要客户端的玩家。Carl Mod 自带的 `ServerDummy.Spawn` 在设置昵称时
  `NicknameSync` 还没有初始化，会抛出 NullReferenceException；本插件按同样的步骤生成，但先运行 `NicknameSync.Start`。
- **玩家列表和传送**。

## 命令

服务器控制台直接输入；游戏内控制台或 RA 使用时前面加 `/`。

| 命令 | 作用 |
| --- | --- |
| `testkit list` | 列出玩家：ID、昵称、角色、坐标，假人标记 `(dummy)` |
| `testkit dummy ROLE` | 在该角色的出生点生成假人 |
| `testkit dummy ROLE ID` | 在玩家 ID 面前 1.5 米处生成假人，面向该玩家 |
| `testkit dummy ROLE X Y Z` | 在指定坐标生成假人 |
| `testkit remove ID` / `testkit remove all` | 移除一个 / 全部假人（只能移除假人） |
| `testkit tp ID TARGET_ID` / `testkit tp ID X Y Z` | 把玩家传送到另一个玩家处或指定坐标 |

`ROLE` 是 `RoleTypeId` 名称（不区分大小写，如 `ClassD`、`Scp173`）或数字。假人在回合重启时自动移除。
生成假人时服务器日志会出现 `The referenced script on this Behaviour ... is missing!` 和
`Error during IP passthrough processing`，不影响使用。

## 构建和安装

推荐用 `scripts\Install-HelperPlugin.ps1`（需要测试服务器已安装 LabAPI-Mobile）。手动构建：

```powershell
dotnet build plugin\TestKitHelper\TestKitHelper.csproj -c Release `
    -p:CarlManaged="<服务端>\Carl Mod_Data\Managed" -p:LabApiDll="<LabApi.dll 路径>"
```

把 `TestKitHelper.dll` 复制到 `<服务器>\AppData\SCP Secret Laboratory\LabAPI-Mobile\plugins\global\`，重启服务器。
