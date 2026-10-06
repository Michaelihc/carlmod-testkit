# Carl Mod 本地测试工具 - 配置示例
#
# 用法：把本文件复制为 testkit.config.psd1（同一文件夹），只保留要改的项。
# 不创建 testkit.config.psd1 时全部使用下面的默认值。
# 相对路径以本工具所在文件夹为起点。

@{
    # 测试服务器的 UDP 端口。模拟器里连接 10.0.2.2:<端口>。
    Port = 7777

    # 服务端 ZIP。留空时使用 inputs 文件夹里唯一的 *.zip。
    ServerZip = ''

    # 已解压的服务端文件夹（包含 Carl Mod.exe）。设置后不需要 ZIP，也不需要 Python。
    # 该文件夹只会被复制，不会被修改。
    ServerFolder = ''

    # 安卓客户端 APK。留空时使用 inputs 文件夹里唯一的 *.apk 或 *.apk.*（例如 xxx.apk.1）。
    Apk = ''

    # Android SDK 位置。留空时依次使用 ANDROID_SDK_ROOT、ANDROID_HOME、%LOCALAPPDATA%\Android\Sdk。
    # 用户名含中文时建议设成英文路径，例如 'D:\Android\Sdk'（模拟器的 AVD 位置用环境变量 ANDROID_AVD_HOME 修改）。
    AndroidSdk = ''

    # 第一个模拟器：AVD 名称和 adb 序列号（emulator-<控制台端口>，端口为 5554-5682 的偶数）。
    AvdName = 'carlmod_api36'
    Serial  = 'emulator-5554'

    # 第二个模拟器（双客户端测试）。
    SecondAvdName = 'carlmod_api36_b'
    SecondSerial  = 'emulator-5556'

    # 文件控制台的会话名（服务器以 -key<会话名> 启动）。
    CommandSession = 'testkit'

    # 每次启动前写入 config_gameplay.txt 的配置。afk_time = '0' 关闭挂机踢出。
    ConfigOverrides = @{ afk_time = '0' }
}
