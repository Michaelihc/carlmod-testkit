# Carl Mod local test kit (carlmod-testkit)

[简体中文](README.md) (primary documentation)

Runs a local **Carl Mod dedicated server** and the **real Android client in an Android emulator** on one Windows PC,
for testing server configuration and server-side plugins. Common actions are double-clickable `.cmd` files and a menu;
the scripts and messages are in Simplified Chinese.

> Not affiliated with SCP: Secret Laboratory (Northwood Studios) or Carl Mod. No game files are included; obtain the
> server and the client from official Carl Mod channels. See [NOTICE](NOTICE).

## Requirements

- 64-bit Windows 10 (1803+) or 11 with **Windows Hypervisor Platform (WHPX)** enabled and CPU virtualization on in the BIOS.
- Java 17+ (only to install the Android SDK), Python 3.8+ (only to extract the server ZIP).
- 16 GB RAM (32 GB for two clients), 8+ CPU threads, about 5 GB free next to the kit and about 20 GB (plus 10 GB per
  extra emulator) for the Android SDK and emulator images. The first SDK install downloads about 2 GB.
- Optional: .NET SDK, to build the helper plugin from source.

## Server versions

| Server | Version name (`ServerVersion`) | Tested with this kit |
| --- | --- | --- |
| Carl Mod 0.0.5 | `0.0.5` | Server side only (import, start, commands, LabAPI-Mobile, helper plugin); no 0.0.5 Android client is available |
| Carl Mod 0.0.4 with the deathmatch module (`CarlModExtras.dll`) | `0.0.4-dm` | Server and the 0.0.4 client in the emulator |
| Official Carl Mod 0.0.4 server | `0.0.4` | Server |

**The client and the server must be the same version**: the server refuses a client of another version (version
mismatch), so a 0.0.4 client cannot join a 0.0.5 server. `check.cmd`, `Show-Status.ps1` and the menu show both versions
and warn when they differ.

- `inputs\` may hold one server ZIP per version (and one APK). The import reads the game version from the server's
  `Assembly-CSharp.dll` and extracts each version to `.runtime\server-original-<version name>`. The 0.0.5 ZIP's top-level
  folder (`Carl Mod Server - 0.0.5\`), its backslash entry names and the distributor's `Assembly-CSharp.dll.pre_*.bak`
  files are handled (`.bak` files are not extracted).
- Test servers are separate per version: `.runtime\server-<port>-<version name>` (e.g. `server-7777-0.0.5`), each with its
  own configs, LabAPI-Mobile install and plugins.
- Which version is used: the `ServerVersion` setting or the scripts' `-ServerVersion` parameter
  (`.\scripts\Start-All.ps1 -ServerVersion 0.0.5`). Without it, a single imported version is used; with several, the one
  matching the APK's version. Otherwise the scripts ask you to set `ServerVersion`. `0.0.4` prefers the official build and
  also matches the deathmatch build when only that one is imported.

## First run

1. Put the Carl Mod Windows server ZIP(s) and the Android client APK (`.apk` or `.apk.1`) into `inputs\`.
2. `check.cmd` — prerequisites check; fix every `[失败]` (failed) item.
3. `setup.cmd` — extracts each server ZIP, installs the Android SDK and creates the AVD `carlmod_api36` (API 36 x86_64).
4. `start-all.cmd` — starts the server on UDP 7777, boots the emulator, installs and launches the client and joins
   `10.0.2.2:7777` through the Direct Connect menu.
5. `send-command.cmd` then `forcestart` — starts the round.
6. `stop-all.cmd` — stops the emulators and servers this kit started.

`menu.cmd` offers all actions in one menu. Every action is also a script in `scripts\` (see the help block at the top of
each script). Settings: copy `testkit.config.example.psd1` to `testkit.config.psd1` (port, server version, input paths,
SDK path, AVD names and serials, `config_gameplay.txt` overrides).

## Behaviour worth knowing

- Inputs are never modified. Test servers are copies in `.runtime\server-<port>-<version name>\`; everything generated
  stays in `.runtime\`.
- `hoster_policy.txt` (`gamedir_for_configs: true`) keeps configs, bans and logs in the server copy's `AppData\`. The one
  exception is the server's player-prefs file `%APPDATA%\SCP Secret Laboratory\registry.txt`: its path is bound before the
  policy is read, and round restarts update its `LastRoundrestartTime` and `SrvSp_*` keys.
- Busy UDP ports are refused. Servers are stopped only by the recorded PID after checking that the process is
  `Carl Mod.exe` with the matching `-port`; emulators only with `adb emu kill` for their serial.
- `afk_time: 0` is set by default; otherwise a lone client standing still is kicked after about 90 s.
- Commands go through the server's file console (`-key<session>`), which does not return command text. The script prints
  new server-log lines instead; with the TestKitHelper plugin the console output is mirrored into the log. Remote Admin
  commands (`/` prefix) execute but their replies are not shown. Each command also logs a harmless
  `Error while sending message`.
- The Remote Admin panel may not open on the emulator. Use the in-game console with `/` commands after granting the
  client RA access with `scripts\Grant-RemoteAdmin.ps1 -Restart` (reads the client's `device_…@device` ID from the log).
- Use the API 36 image: the API 34 image's ARM translator lacks the AArch64 `SEVL` instruction and the client dies with SIGILL.
- Windows power-throttles a background emulator window (roughly a quarter slower); the scripts opt the qemu process they
  started out of it.
- Second client: `scripts\Install-AndroidSdk.ps1 -Second` once, then `scripts\Start-All.ps1 -Second`
  (AVD `carlmod_api36_b`, `emulator-5556`).
- With no real player connected the server enters idle mode after about 5 s and runs one frame per second, so command
  output may arrive after `Send-ServerCommand.ps1` stops waiting. Use `-WaitSec 5`, or add `idle_mode_enabled = 'false'`
  to `ConfigOverrides`.

## Optional: LabAPI-Mobile and the helper plugin

`scripts\Install-LabApiMobile.ps1` installs the latest [LabAPI-Mobile](https://github.com/Michaelihc/labapimobile)
release into the test server of the selected version (server stopped). It supports 0.0.4 (both servers) and 0.0.5; 0.0.5
needs 1.1.7-mobile.5 or later. Install it again for each server version.

`scripts\Install-HelperPlugin.ps1` builds (or downloads) `TestKitHelper`, which mirrors console output into the server log
and adds `testkit list | dummy ROLE [ID | X Y Z] | remove ID|all | tp ID TARGET_ID|X Y Z` (server-side dummy players
without a second device). One DLL serves 0.0.4 and 0.0.5: on 0.0.5 it spawns dummies with the game's own
`ServerDummy.Spawn` (device IDs `device_dummy_…@device`; `list` prints `device=`), on 0.0.4, whose `ServerDummy.Spawn` fails
when it sets the nickname, it runs the same steps itself (`list` prints `userid=`). `testkit` without arguments shows which
one is used. It installs into the running test server, otherwise into the selected version's test server. The command
has no permission check; use it on local test servers only.

## License

MIT, see [LICENSE](LICENSE).
