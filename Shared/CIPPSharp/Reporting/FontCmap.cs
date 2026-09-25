using System.Collections.Generic;
using System.Text;

namespace CIPP.Reporting
{
    /// <summary>
    /// A minimal read-only TrueType/OpenType <c>cmap</c> reader: enough to enumerate the Unicode code
    /// points a font can draw, so the bundled emoji fallback is the single source of truth for both what
    /// <see cref="ReportMarkdown.Sanitize"/> keeps and which ranges OfficeIMO routes to it. Reads the
    /// Windows Unicode BMP subtable (format 4) and the full-repertoire subtable (format 12, which carries
    /// the astral emoji); all multi-byte fields are big-endian per the sfnt spec.
    /// </summary>
    internal static class FontCmap
    {
        public static IEnumerable<int> ReadCodepoints(byte[] f)
        {
            var result = new List<int>();
            if (f.Length < 12) return result;

            var numTables = U16(f, 4);
            var cmapOffset = -1;
            for (var i = 0; i < numTables; i++)
            {
                var rec = 12 + i * 16;
                if (rec + 16 > f.Length) break;
                if (Encoding.ASCII.GetString(f, rec, 4) == "cmap") { cmapOffset = (int)U32(f, rec + 8); break; }
            }
            if (cmapOffset < 0 || cmapOffset + 4 > f.Length) return result;

            var subCount = U16(f, cmapOffset + 2);
            var best4 = -1;
            var best12 = -1;
            for (var i = 0; i < subCount; i++)
            {
                var p = cmapOffset + 4 + i * 8;
                if (p + 8 > f.Length) break;
                var platform = U16(f, p);
                var encoding = U16(f, p + 2);
                var subOffset = cmapOffset + (int)U32(f, p + 4);
                if (subOffset + 2 > f.Length) continue;
                var format = U16(f, subOffset);
                if (format == 12 && (platform == 3 && encoding == 10 || platform == 0)) best12 = subOffset;
                else if (format == 4 && best4 < 0 && (platform == 3 && encoding == 1 || platform == 0)) best4 = subOffset;
            }

            if (best12 >= 0) ReadFormat12(f, best12, result);
            if (best4 >= 0) ReadFormat4(f, best4, result);
            return result;
        }

        private static void ReadFormat4(byte[] f, int o, List<int> outp)
        {
            var segX2 = U16(f, o + 6);
            var segCount = segX2 / 2;
            var endO = o + 14;
            var startO = endO + segX2 + 2;
            var deltaO = startO + segX2;
            var rangeO = deltaO + segX2;
            for (var s = 0; s < segCount; s++)
            {
                var end = U16(f, endO + s * 2);
                var start = U16(f, startO + s * 2);
                if (start == 0xFFFF) continue;
                var delta = U16(f, deltaO + s * 2);
                var ro = U16(f, rangeO + s * 2);
                for (var c = start; c <= end; c++)
                {
                    int g;
                    if (ro == 0) g = (c + delta) & 0xFFFF;
                    else
                    {
                        var gi = rangeO + s * 2 + ro + (c - start) * 2;
                        if (gi + 2 > f.Length) continue;
                        g = U16(f, gi);
                        if (g != 0) g = (g + delta) & 0xFFFF;
                    }
                    if (g != 0) outp.Add(c);
                }
            }
        }

        private static void ReadFormat12(byte[] f, int o, List<int> outp)
        {
            var nGroups = U32(f, o + 12);
            for (long i = 0; i < nGroups; i++)
            {
                var p = o + 16 + (int)i * 12;
                if (p + 12 > f.Length) break;
                var startChar = U32(f, p);
                var endChar = U32(f, p + 4);
                for (var c = startChar; c <= endChar && c <= 0x10FFFF; c++) outp.Add((int)c);
            }
        }

        private static int U16(byte[] f, int o) => (f[o] << 8) | f[o + 1];
        private static long U32(byte[] f, int o) => ((long)f[o] << 24) | ((long)f[o + 1] << 16) | ((long)f[o + 2] << 8) | f[o + 3];
    }
}
