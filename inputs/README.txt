把下面的文件放在这个文件夹里（从 Carl Mod 官方渠道获取，本项目不提供）：

1. Carl Mod Windows 服务端 ZIP（压缩包里有 "Carl Mod.exe"），文件名随意，扩展名 .zip。
   支持 0.0.4 和 0.0.5，可以放多个版本，每个版本一个。
2. Carl Mod 安卓客户端 APK，扩展名 .apk 或 .apk.1 之类均可，只放一个。
   客户端和服务端的版本必须相同（0.0.4 的客户端不能加入 0.0.5 的服务器）。

这些文件只会被读取和复制，不会被修改，也不会被提交到 Git。
如果文件在别的位置，或已经有解压好的服务端文件夹，可以在 testkit.config.psd1 里设置
ServerZip / ServerFolder / Apk（见 testkit.config.example.psd1）。

Put the Carl Mod Windows server ZIP(s) (0.0.4 and/or 0.0.5, one per version) and the Android client APK
(one; its version must match the server's) here. They are only read and copied, never modified, and are
ignored by Git.
