using System;
using System.Reflection;
using Mirror;
using PlayerRoles;
using PlayerRoles.FirstPersonControl;
using RelativePositioning;
using UnityEngine;

namespace CarlModTestKit
{
    /// <summary>
    /// Server-side dummy players (no phone needed).
    /// Carl Mod 0.0.5 fixed the game's ServerDummy.Spawn (NicknameSync.Awake sets the hub reference), so it is used
    /// there. On 0.0.4, ServerDummy.Spawn sets the nickname while NicknameSync's hub reference is still null and throws a
    /// NullReferenceException in NicknameSync.SetNick; the same steps run here with NicknameSync.Start called first.
    /// The builds are told apart by their members, and members that only one build has are bound by reflection
    /// (a missing member breaks the JIT of the method that references it).
    /// </summary>
    internal static class DummyFactory
    {
        private const BindingFlags Any = BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public;

        private static readonly FieldInfo HubField = typeof(ServerDummy).GetField("_hub", Any);
        private static readonly FieldInfo ConnectionField = typeof(ServerDummy).GetField("_connection", Any);
        private static readonly MethodInfo NicknameStart = typeof(NicknameSync).GetMethod("Start", Any | BindingFlags.DeclaredOnly);

        /// <summary>True when the game's own ServerDummy.Spawn works (Carl Mod 0.0.5: NicknameSync declares Awake).</summary>
        public static readonly bool NativeSpawn = typeof(NicknameSync).GetMethod("Awake", Any | BindingFlags.DeclaredOnly) != null;

        /// <summary>True when players are identified by device ID (Carl Mod 0.0.5: CharacterClassManager.DeviceId, equal to UserId).</summary>
        public static readonly bool DeviceIds = typeof(CharacterClassManager).GetProperty("DeviceId", Any) != null;

        public static string SpawnMode => NativeSpawn
            ? "game ServerDummy.Spawn"
            : "ServerDummy.Spawn steps with NicknameSync.Start first (Carl Mod 0.0.4 workaround)";

        /// <param name="position">World position, or null to use the role's spawnpoint.</param>
        /// <param name="yaw">Horizontal view angle in degrees (only used with a position).</param>
        public static ReferenceHub Spawn(RoleTypeId role, Vector3? position, float yaw) =>
            NativeSpawn ? SpawnNative(role, position, yaw) : SpawnWithWorkaround(role, position, yaw);

        private static ReferenceHub SpawnNative(RoleTypeId role, Vector3? position, float yaw)
        {
            // The game's Spawn always places the dummy at the given position, so pick the role's spawnpoint first.
            Vector3 at = Vector3.zero;
            if (position.HasValue)
                at = position.Value;
            else if (TryGetSpawnpoint(role, out Vector3 spawnpoint, out float spawnYaw))
            {
                at = spawnpoint;
                yaw = spawnYaw;
            }

            return ServerDummy.Spawn(role, at, Quaternion.Euler(0f, yaw, 0f));
        }

        private static bool TryGetSpawnpoint(RoleTypeId role, out Vector3 position, out float yaw)
        {
            position = Vector3.zero;
            yaw = 0f;
            return PlayerRoleLoader.TryGetRoleTemplate(role, out PlayerRoleBase template)
                && template is IFpcRole fpc
                && fpc.SpawnpointHandler != null
                && fpc.SpawnpointHandler.TryGetSpawnpoint(out position, out yaw);
        }

        private static ReferenceHub SpawnWithWorkaround(RoleTypeId role, Vector3? position, float yaw)
        {
            if (!NetworkServer.active || NetworkManager.singleton == null || NetworkManager.singleton.playerPrefab == null)
                throw new InvalidOperationException("The server player prefab is unavailable.");
            if (HubField == null || ConnectionField == null || NicknameStart == null)
                throw new InvalidOperationException("ServerDummy/NicknameSync members not found; this game build is not supported.");

            int id = -1;
            while (NetworkServer.connections.ContainsKey(id))
                id--;

            var connection = new ServerDummyConnection(id);
            Vector3 start = position ?? Vector3.zero;
            GameObject go = null;
            try
            {
                go = UnityEngine.Object.Instantiate(NetworkManager.singleton.playerPrefab, start, Quaternion.Euler(0f, yaw, 0f));
                ReferenceHub hub = go.GetComponent<ReferenceHub>();
                if (hub == null)
                    throw new InvalidOperationException("The player prefab has no ReferenceHub.");

                ServerDummy dummy = go.AddComponent<ServerDummy>();
                HubField.SetValue(dummy, hub);
                ConnectionField.SetValue(dummy, connection);
                NetworkServer.connections.Add(id, connection);
                if (!NetworkServer.AddPlayerForConnection(connection, go))
                    throw new InvalidOperationException("Mirror could not register the dummy player.");

                hub.characterClassManager.UserId = connection.UserId;
                NicknameStart.Invoke(hub.nicknameSync, null);
                hub.nicknameSync.UpdateNickname("Dummy " + hub.PlayerId);

                RoleSpawnFlags flags = position.HasValue ? RoleSpawnFlags.AssignInventory : RoleSpawnFlags.AssignInventory | RoleSpawnFlags.UseSpawnpoint;
                hub.roleManager.ServerSetRole(role, RoleChangeReason.RemoteAdmin, flags);
                if (position.HasValue && hub.roleManager.CurrentRole is IFpcRole fpc)
                {
                    fpc.FpcModule.ServerOverridePosition(position.Value, Vector3.zero);
                    fpc.FpcModule.Motor.ReceivedPosition = new RelativePosition(position.Value);
                    fpc.FpcModule.MouseLook.CurrentHorizontal = yaw;
                }

                return hub;
            }
            catch
            {
                connection.Disconnect();
                if (go != null && !go.GetComponent<NetworkIdentity>().isServer)
                    UnityEngine.Object.Destroy(go);
                throw;
            }
        }

        public static bool IsDummy(ReferenceHub hub) => hub != null && hub.GetComponent<ServerDummy>() != null;

        /// <summary>Disconnects a dummy (the same path a round restart uses).</summary>
        public static bool Remove(ReferenceHub hub)
        {
            ServerDummy dummy = hub == null ? null : hub.GetComponent<ServerDummy>();
            if (dummy == null)
                return false;

            var connection = ConnectionField?.GetValue(dummy) as NetworkConnection;
            if (connection == null)
                return false;

            connection.Disconnect();
            return true;
        }
    }
}
