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

## First run

1. Put the Carl Mod Windows server ZIP and the Android client APK (`.apk` or `.apk.1`) into `inputs\`.
2. `check.cmd` — prerequisites check; fix every `[失败]` (failed) item.
3. `setup.cmd` — extracts the server, installs the Android SDK and creates the AVD `carlmod_api36` (API 36 x86_64).
4. `start-all.cmd` — starts the server on UDP 7777, boots the emulator, installs and launches the client and joins
   `10.0.2.2:7777` through the Direct Connect menu.
5. `send-command.cmd` then `forcestart` — starts the round.
6. `stop-all.cmd` — stops the emulators and servers this kit started.

`menu.cmd` offers all actions in one menu. Every action is also a script in `scripts\` (see the help block at the top of
each script). Settings: copy `testkit.config.example.psd1` to `testkit.config.psd1` (port, input paths, SDK path, AVD
names and serials, `config_gameplay.txt` overrides).

## Behaviour worth knowing

- Inputs are never modified. Test servers are copies in `.runtime\server-<port>\`; everything generated stays in `.runtime\`.
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

## Optional: LabAPI-Mobile and the helper plugin

`scripts\Install-LabApiMobile.ps1` installs [LabAPI-Mobile](https://github.com/Michaelihc/labapimobile) into the test
server (server stopped). `scripts\Install-HelperPlugin.ps1` builds (or downloads) `TestKitHelper`, which mirrors console
output into the server log and adds `testkit list | dummy ROLE [ID | X Y Z] | remove ID|all | tp ID TARGET_ID|X Y Z`
(server-side dummy players without a second device). The command has no permission check; use it on local test servers only.

## License

MIT, see [LICENSE](LICENSE).
