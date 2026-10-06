using System;
using UnityEngine;

namespace CarlModTestKit
{
    /// <summary>
    /// Copies every server console line into the Unity log (-logFile) with a "[console] " prefix on each line.
    /// With the file console (-key&lt;session&gt;) the console text is otherwise not readable anywhere.
    /// </summary>
    internal sealed class ConsoleMirror : IOutput
    {
        private const string Prefix = "[console] ";

        private static readonly ConsoleMirror Instance = new ConsoleMirror();

        [ThreadStatic]
        private static bool _writing;

        public static void Attach()
        {
            var outputs = ServerConsole.ConsoleOutputs;
            if (outputs != null && !outputs.Contains(Instance))
                outputs.Add(Instance);
        }

        public static void Detach() => ServerConsole.ConsoleOutputs?.Remove(Instance);

        public void Print(string text) => Write(text);

        public void Print(string text, ConsoleColor c) => Write(text);

        public void Print(string text, ConsoleColor c, Color rgbColor) => Write(text);

        private static void Write(string text)
        {
            if (string.IsNullOrEmpty(text) || _writing)
                return;

            _writing = true;
            try
            {
                Debug.Log(Prefix + text.Replace("\r", string.Empty).Replace("\n", "\n" + Prefix));
            }
            finally
            {
                _writing = false;
            }
        }
    }
}
