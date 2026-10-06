using System;
using System.Globalization;
using System.Text;
using CommandSystem;
using PlayerRoles;
using PlayerRoles.FirstPersonControl;
using UnityEngine;

namespace CarlModTestKit
{
    /// <summary>
    /// "testkit" command for the server console and Remote Admin. No permission check: local test servers only.
    /// </summary>
    [CommandHandler(typeof(GameConsoleCommandHandler))]
    [CommandHandler(typeof(RemoteAdminCommandHandler))]
    public sealed class TestKitCommand : ICommand
    {
        // No angle brackets: the server console treats <word> as rich-text tags.
        private const string Usage =
            "testkit list                         list players (id, nick, role, position)\n" +
            "testkit dummy ROLE [ID | X Y Z]      spawn a dummy at the role spawnpoint, in front of player ID, or at X Y Z\n" +
            "testkit remove ID|all                remove one dummy or all dummies\n" +
            "testkit tp ID TARGET_ID|X Y Z        move a player to another player or to X Y Z\n" +
            "ROLE: ClassD, Scientist, FacilityGuard, NtfPrivate, ChaosRifleman, Scp173, Scp049, ... or its number";

        public string Command => "testkit";

        public string[] Aliases => Array.Empty<string>();

        public string Description => "Local test helper (carlmod-testkit): list, dummy, remove, tp.";

        public bool Execute(ArraySegment<string> arguments, ICommandSender sender, out string response)
        {
            try
            {
                string sub = arguments.Count > 0 ? arguments.At(0).ToLowerInvariant() : "help";
                switch (sub)
                {
                    case "list":
                        response = List();
                        return true;
                    case "dummy":
                        return Dummy(arguments, out response);
                    case "remove":
                        return Remove(arguments, out response);
                    case "tp":
                        return Teleport(arguments, out response);
                    default:
                        response = Usage;
                        return sub == "help";
                }
            }
            catch (Exception e)
            {
                response = "testkit failed: " + e.GetType().Name + ": " + e.Message;
                return false;
            }
        }

        private static string List()
        {
            var sb = new StringBuilder("players:");
            foreach (ReferenceHub hub in ReferenceHub.AllHubs)
            {
                if (hub == ReferenceHub.HostHub)
                    continue; // the dedicated server's own player object

                sb.Append("\n  id=").Append(hub.PlayerId)
                    .Append(" nick=").Append(hub.nicknameSync.MyNick)
                    .Append(" role=").Append(hub.roleManager.CurrentRole.RoleTypeId)
                    .Append(" pos=").Append(FormatPosition(hub))
                    .Append(DummyFactory.IsDummy(hub) ? " (dummy)" : string.Empty);
            }

            return sb.ToString();
        }

        private static bool Dummy(ArraySegment<string> args, out string response)
        {
            if (args.Count < 2 || !TryParseRole(args.At(1), out RoleTypeId role))
            {
                response = "unknown or missing ROLE.\n" + Usage;
                return false;
            }

            Vector3? position = null;
            float yaw = 0f;
            if (args.Count >= 5)
            {
                if (!TryParseVector(args, 2, out Vector3 p))
                {
                    response = "x y z must be numbers.";
                    return false;
                }

                position = p;
            }
            else if (args.Count >= 3)
            {
                if (!TryGetFpc(args.At(2), out ReferenceHub anchor, out IFpcRole anchorFpc, out response))
                    return false;

                float anchorYaw = anchorFpc.FpcModule.MouseLook.CurrentHorizontal;
                position = anchorFpc.FpcModule.Position + Quaternion.Euler(0f, anchorYaw, 0f) * Vector3.forward * 1.5f;
                yaw = anchorYaw + 180f;
            }

            ReferenceHub hub = DummyFactory.Spawn(role, position, yaw);
            response = "spawned dummy id=" + hub.PlayerId + " role=" + hub.roleManager.CurrentRole.RoleTypeId
                + (position.HasValue ? " pos=" + FormatPosition(hub) : " at the role spawnpoint");
            return true;
        }

        private static bool Remove(ArraySegment<string> args, out string response)
        {
            if (args.Count < 2)
            {
                response = "usage: testkit remove ID|all";
                return false;
            }

            if (args.At(1).Equals("all", StringComparison.OrdinalIgnoreCase))
            {
                var dummies = new System.Collections.Generic.List<ReferenceHub>();
                foreach (ReferenceHub hub in ReferenceHub.AllHubs)
                {
                    if (DummyFactory.IsDummy(hub))
                        dummies.Add(hub);
                }

                int removed = 0;
                foreach (ReferenceHub hub in dummies)
                {
                    if (DummyFactory.Remove(hub))
                        removed++;
                }

                response = "removed " + removed + " dummies";
                return true;
            }

            if (!TryGetHub(args.At(1), out ReferenceHub target, out response))
                return false;

            if (!DummyFactory.Remove(target))
            {
                response = "player " + target.PlayerId + " is not a dummy; only dummies can be removed.";
                return false;
            }

            response = "removed dummy id=" + target.PlayerId;
            return true;
        }

        private static bool Teleport(ArraySegment<string> args, out string response)
        {
            if (args.Count < 3)
            {
                response = "usage: testkit tp ID TARGET_ID|X Y Z";
                return false;
            }

            if (!TryGetFpc(args.At(1), out ReferenceHub hub, out IFpcRole fpc, out response))
                return false;

            Vector3 destination;
            if (args.Count >= 5)
            {
                if (!TryParseVector(args, 2, out destination))
                {
                    response = "x y z must be numbers.";
                    return false;
                }
            }
            else
            {
                if (!TryGetFpc(args.At(2), out ReferenceHub _, out IFpcRole targetFpc, out response))
                    return false;

                destination = targetFpc.FpcModule.Position;
            }

            fpc.FpcModule.ServerOverridePosition(destination, Vector3.zero);
            response = "moved id=" + hub.PlayerId + " to " + destination.ToString("F1");
            return true;
        }

        private static bool TryParseRole(string text, out RoleTypeId role)
        {
            if (int.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out int number))
            {
                role = (RoleTypeId)number;
                return Enum.IsDefined(typeof(RoleTypeId), role);
            }

            return Enum.TryParse(text, true, out role) && Enum.IsDefined(typeof(RoleTypeId), role);
        }

        private static bool TryParseVector(ArraySegment<string> args, int start, out Vector3 value)
        {
            value = default;
            if (!float.TryParse(args.At(start), NumberStyles.Float, CultureInfo.InvariantCulture, out float x)
                || !float.TryParse(args.At(start + 1), NumberStyles.Float, CultureInfo.InvariantCulture, out float y)
                || !float.TryParse(args.At(start + 2), NumberStyles.Float, CultureInfo.InvariantCulture, out float z))
                return false;

            value = new Vector3(x, y, z);
            return true;
        }

        private static bool TryGetHub(string idText, out ReferenceHub hub, out string response)
        {
            hub = null;
            if (!int.TryParse(idText, NumberStyles.Integer, CultureInfo.InvariantCulture, out int id) || !ReferenceHub.TryGetHub(id, out hub))
            {
                response = "no player with id " + idText + " (see: testkit list)";
                return false;
            }

            response = null;
            return true;
        }

        private static bool TryGetFpc(string idText, out ReferenceHub hub, out IFpcRole fpc, out string response)
        {
            fpc = null;
            if (!TryGetHub(idText, out hub, out response))
                return false;

            fpc = hub.roleManager.CurrentRole as IFpcRole;
            if (fpc == null)
            {
                response = "player " + hub.PlayerId + " has no body (role " + hub.roleManager.CurrentRole.RoleTypeId + ").";
                return false;
            }

            return true;
        }

        private static string FormatPosition(ReferenceHub hub) =>
            hub.roleManager.CurrentRole is IFpcRole fpc ? fpc.FpcModule.Position.ToString("F1") : "-";
    }
}
