把下面两个文件放在这个文件夹里（从 Carl Mod 官方渠道获取，本项目不提供）：

1. Carl Mod Windows 服务端 ZIP（压缩包里有 "Carl Mod.exe"），文件名随意，扩展名 .zip
2. Carl Mod 安卓客户端 APK，扩展名 .apk 或 .apk.1 之类均可

每种只放一个。这两个文件只会被读取和复制，不会被修改，也不会被提交到 Git。
如果文件在别的位置，或已经有解压好的服务端文件夹，可以在 testkit.config.psd1 里设置
ServerZip / ServerFolder / Apk（见 testkit.config.example.psd1）。

Put the Carl Mod Windows server ZIP and the Android client APK here (one of each).
They are only read and copied, never modified, and are ignored by Git.
