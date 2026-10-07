using System;
using LabApi.Events.Handlers;
using LabApi.Features.Console;
using LabApi.Loader.Features.Plugins;

namespace CarlModTestKit
{
    /// <summary>
    /// Local test helper for Carl Mod servers: mirrors console output into the Unity log (the file console
    /// never returns command text), spawns server-side dummy players and lists/moves players.
    /// For local test servers only: the "testkit" command has no permission check.
    /// </summary>
    public sealed class TestKitHelperPlugin : Plugin
    {
        private static bool _announced;

        public override string Name => "TestKitHelper";

        public override string Description => "Carl Mod local test helper: console mirror, dummy players, player list.";

        public override string Author => "carlmod-testkit";

        public override Version Version => new Version(1, 1, 0);

        public override Version RequiredApiVersion => new Version(1, 0, 0);

        public override void Enable()
        {
            ConsoleMirror.Attach();
            // ServerConsole replaces its output list after plugins are enabled, so attach again later.
            ServerEvents.WaitingForPlayers += OnWaitingForPlayers;
            ServerEvents.RoundStarted += ConsoleMirror.Attach;
        }

        public override void Disable()
        {
            ServerEvents.WaitingForPlayers -= OnWaitingForPlayers;
            ServerEvents.RoundStarted -= ConsoleMirror.Attach;
            ConsoleMirror.Detach();
        }

        private static void OnWaitingForPlayers()
        {
            ConsoleMirror.Attach();
            if (_announced)
                return;

            // Logged once the mirror is attached, so that it also reaches the log with the file console.
            _announced = true;
            Logger.Info("TestKitHelper " + typeof(TestKitHelperPlugin).Assembly.GetName().Version.ToString(3) + ", dummy players: " + DummyFactory.SpawnMode + ".");
        }
    }
}
