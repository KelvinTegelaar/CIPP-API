using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

namespace CIPP.Reporting
{
    /// <summary>
    /// Resolves an emoji grapheme cluster to its bundled Twemoji colour PNG. The full 72x72 Twemoji set
    /// ships as individual files under <c>twemoji/</c> beside the assembly (one small file per emoji, so a
    /// render only touches the handful it embeds). The renderer places each as an inline colour image, the
    /// way the client's react-pdf reports did - the standard PDF fonts and OfficeIMO's embedding are
    /// monochrome-only, so this is the only route to colour emoji. Absent, emoji fall back to the bundled
    /// monochrome font.
    /// </summary>
    internal static class TwemojiAssets
    {
        private static readonly Lazy<string?> Dir = new(() =>
        {
            try
            {
                var d = Path.GetDirectoryName(typeof(TwemojiAssets).Assembly.Location);
                if (string.IsNullOrEmpty(d)) return null;
                var t = Path.Combine(d, "twemoji");
                return Directory.Exists(t) ? t : null;
            }
            catch { return null; }
        });

        // The set of available basenames (e.g. "26a0", "1f1fa-1f1f8"), read once, so a lookup is O(1) and
        // never hits the disk for an emoji we don't ship.
        private static readonly Lazy<HashSet<string>> Available = new(() =>
        {
            var set = new HashSet<string>(StringComparer.Ordinal);
            var dir = Dir.Value;
            if (dir is null) return set;
            try { foreach (var f in Directory.EnumerateFiles(dir, "*.png")) set.Add(Path.GetFileNameWithoutExtension(f)); }
            catch { }
            return set;
        });

        // Bytes read on first use for an emoji and kept (a used emoji is at most ~5 KB; the whole set is
        // ~4 MB), so a report referencing the same emoji many times reads the file once.
        private static readonly ConcurrentDictionary<string, byte[]?> Cache = new(StringComparer.Ordinal);

        public static bool Enabled => Dir.Value is not null && Available.Value.Count > 0;

        /// <summary>
        /// The Twemoji basename for a grapheme cluster (its toCodePoint rule): drop the VS16 emoji-style
        /// selector unless the cluster is a ZWJ sequence, then join the code points as lowercase hex with
        /// '-'. Null if the cluster has no drawable code point.
        /// </summary>
        public static string? Key(string cluster)
        {
            if (string.IsNullOrEmpty(cluster)) return null;
            var hasZwj = cluster.IndexOf('‍') >= 0;
            var sb = new StringBuilder();
            var any = false;
            for (var i = 0; i < cluster.Length;)
            {
                int cp;
                if (char.IsHighSurrogate(cluster[i]) && i + 1 < cluster.Length && char.IsLowSurrogate(cluster[i + 1]))
                { cp = char.ConvertToUtf32(cluster[i], cluster[i + 1]); i += 2; }
                else { cp = cluster[i]; i++; }
                if (!hasZwj && cp == 0xFE0F) continue;
                if (any) sb.Append('-');
                sb.Append(cp.ToString("x", CultureInfo.InvariantCulture));
                any = true;
            }
            return any ? sb.ToString() : null;
        }

        /// <summary>True when a bundled Twemoji PNG exists for this grapheme cluster.</summary>
        public static bool Has(string cluster)
        {
            if (!Enabled) return false;
            var k = Key(cluster);
            return k is not null && Available.Value.Contains(k);
        }

        /// <summary>The PNG bytes for a grapheme cluster, or null if none is bundled.</summary>
        public static byte[]? Bytes(string cluster)
        {
            var k = Key(cluster);
            if (k is null || !Available.Value.Contains(k)) return null;
            return Cache.GetOrAdd(k, key =>
            {
                try { return File.ReadAllBytes(Path.Combine(Dir.Value!, key + ".png")); }
                catch { return null; }
            });
        }
    }
}
