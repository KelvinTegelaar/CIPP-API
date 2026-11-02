using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace CIPP
{
    /// <summary>
    /// Host-scoped inverted index over the shipped CIPP documentation, backing the SearchDocs
    /// and GetDoc MCP tools.
    ///
    /// This lives in C# for two reasons, both measured rather than assumed. Tokenising the
    /// 2 MB corpus in PowerShell took 26 seconds, because the inner loop runs some 400k times
    /// and PowerShell pays interpreter and call overhead on every iteration; the same work here
    /// is well under a second. More importantly the index is static, so - exactly as with
    /// TestDataCache - the DLL is loaded once per host and every PowerShell worker on that host
    /// shares this one instance. A PowerShell $script: cache is per-runspace, so a worker pool
    /// would have rebuilt the whole index once per worker, and warming it on a timer would only
    /// ever have warmed the single runspace the timer happened to run in.
    ///
    /// The caller supplies pages and chunks already parsed and linked (that logic stays in
    /// PowerShell, where it is cheap and readable); this class owns tokenisation, the postings
    /// map, BM25 scoring, fuzzy vocabulary matching and excerpting.
    /// </summary>
    public static class DocsIndex
    {
        // ── BM25 parameters ──
        private const double K1 = 1.2;
        private const double B = 0.75;

        // Damping for expanded terms. A synonym or a typo-correction can promote a page but must
        // never outrank a chunk that matched what the caller actually typed.
        private const double SynonymWeight = 0.55;
        private const double FuzzyWeight = 0.40;

        // ── State ──
        private static readonly object _buildLock = new();
        private static volatile IndexData? _current;

        public sealed class PageRecord
        {
            public string RelativePath = "";
            public string Title = "";
            public string Description = "";
            public string Breadcrumb = "";
            public string Slug = "";
            public string? DocsUrl;
            public string GitHubUrl = "";
            public string? AppPath;
            public bool Published;
            public List<string> Headings = new();
        }

        internal sealed class ChunkRecord
        {
            public int PageIndex;
            public string Heading = "";
            public string Anchor = "";
            public string Text = "";
            public int Length;
        }

        internal sealed class IndexData
        {
            public string Key = "";
            public List<PageRecord> Pages = new();
            public List<ChunkRecord> Chunks = new();
            public Dictionary<string, List<(int ChunkId, int Frequency)>> Postings =
                new(StringComparer.Ordinal);
            public double AverageLength = 1;
        }

        /// <summary>
        /// Accumulates an index. Handed back to the caller as an instance rather than kept in a
        /// static: a half-built index must never be reachable from another worker, and an
        /// abandoned build (an exception mid-loop) has to collect rather than wedge the host.
        /// </summary>
        public sealed class Builder
        {
            internal readonly IndexData Data;
            internal Builder(string key) { Data = new IndexData { Key = key }; }

            public int PageCount => Data.Pages.Count;
            public int ChunkCount => Data.Chunks.Count;

            public int AddPage(string relativePath, string title, string description,
                string breadcrumb, string slug, string? docsUrl, string gitHubUrl, string? appPath,
                bool published)
            {
                Data.Pages.Add(new PageRecord
                {
                    RelativePath = relativePath ?? "",
                    Title = title ?? "",
                    Description = description ?? "",
                    Breadcrumb = breadcrumb ?? "",
                    Slug = slug ?? "",
                    DocsUrl = string.IsNullOrWhiteSpace(docsUrl) ? null : docsUrl,
                    GitHubUrl = gitHubUrl ?? "",
                    AppPath = string.IsNullOrWhiteSpace(appPath) ? null : appPath,
                    Published = published
                });
                return Data.Pages.Count - 1;
            }

            /// <summary>
            /// Adds one heading-delimited chunk. The page's title, description and slug words are
            /// folded in at a boost weight rather than being repeated into the text by the caller:
            /// a 20-section page would otherwise have its title tokenised 20 times over.
            /// </summary>
            public void AddChunk(int pageIndex, string? heading, string? anchor, string? text)
            {
                if (pageIndex < 0 || pageIndex >= Data.Pages.Count) return;

                var page = Data.Pages[pageIndex];
                heading ??= "";
                text ??= "";

                var frequency = new Dictionary<string, int>(StringComparer.Ordinal);
                int length = 0;

                // Weights: what a chunk is *about* outranks a word it merely contains.
                length += Accumulate(frequency, page.Title, 3);
                length += Accumulate(frequency, heading, 3);
                length += Accumulate(frequency, page.Description, 2);
                length += Accumulate(frequency, page.Slug.Replace('/', ' ').Replace('-', ' '), 1);
                length += Accumulate(frequency, text, 1);

                int chunkId = Data.Chunks.Count;
                foreach (var pair in frequency)
                {
                    if (!Data.Postings.TryGetValue(pair.Key, out var list))
                    {
                        list = new List<(int, int)>();
                        Data.Postings[pair.Key] = list;
                    }
                    list.Add((chunkId, pair.Value));
                }

                if (!string.IsNullOrEmpty(heading)) page.Headings.Add(heading);

                Data.Chunks.Add(new ChunkRecord
                {
                    PageIndex = pageIndex,
                    Heading = heading,
                    Anchor = anchor ?? "",
                    Text = text,
                    Length = length
                });
            }

            private static int Accumulate(Dictionary<string, int> frequency, string text, int weight)
            {
                int added = 0;
                foreach (var token in Tokenize(text))
                {
                    frequency.TryGetValue(token, out int current);
                    frequency[token] = current + weight;
                    added += weight;
                }
                return added;
            }
        }

        /// <summary>
        /// A search's hits plus the total that matched before the per-page cap and limit.
        /// Returned rather than exposed as a static counter: this class is shared by every
        /// worker on the host, so a mutable static would be clobbered by concurrent searches.
        /// </summary>
        public sealed class SearchResult
        {
            public int MatchCount;
            public SearchHit[] Hits = Array.Empty<SearchHit>();
            public string[] Suggestions = Array.Empty<string>();
        }

        /// <summary>Result row handed back to PowerShell, already shaped for the MCP response.</summary>
        public sealed class SearchHit
        {
            public string Title = "";
            public string? Section;
            public string Path = "";
            public string Excerpt = "";
            public string? DocsUrl;
            public string GitHubUrl = "";
            public string? AppPath;
            public string Breadcrumb = "";
            public bool Published;
            public double Score;
        }

        // ────────────────────────────────── Build ──────────────────────────────────

        /// <summary>True when an index for this key is already available on this host.</summary>
        public static bool IsBuilt(string key)
        {
            var current = _current;
            return current != null && string.Equals(current.Key, key, StringComparison.OrdinalIgnoreCase);
        }

        /// <summary>Starts a new index build. The returned builder is the caller's to hold.</summary>
        public static Builder BeginBuild(string key) => new Builder(key);

        /// <summary>
        /// Publishes a completed index. The swap is a single reference assignment to a volatile
        /// field, so a concurrent reader sees either the previous index or the new one, never a
        /// half-populated one. Two workers racing to build simply duplicate the work and the last
        /// to finish wins - both produce the same index.
        /// </summary>
        public static void CommitBuild(Builder builder)
        {
            if (builder == null) throw new ArgumentNullException(nameof(builder));

            builder.Data.AverageLength = builder.Data.Chunks.Count > 0
                ? builder.Data.Chunks.Average(c => (double)c.Length)
                : 1;

            lock (_buildLock) { _current = builder.Data; }
        }

        public static void Clear()
        {
            lock (_buildLock) { _current = null; }
        }

        public static int PageCount => _current?.Pages.Count ?? 0;
        public static int ChunkCount => _current?.Chunks.Count ?? 0;
        public static int TermCount => _current?.Postings.Count ?? 0;

        // ──────────────────────────────── Tokenising ────────────────────────────────

        private static readonly HashSet<string> StopWords = new(StringComparer.Ordinal)
        {
            "the","and","for","are","but","wa","were","been","being","have","ha","had",
            "that","thi","these","those","with","from","into","onto","your","you","their",
            "them","they","it","be","is","of","to","in","on","at","by","or","as",
            "an","if","then","than","so","such","via","per","each","any","more","most",
            "other","some","will","can","may","must","should","would","could","when","where",
            "which","who","what","how","why","here","there","also","about","over","under",
            "after","before","between","both","only","own","same","too","very","just","do",
            "doe","did","done","get","got","make","made","use","used","using","want"
        };

        /// <summary>
        /// The single tokenisation rule, shared by indexing and querying - the two must agree
        /// exactly or a term indexed as 'standard' is never found by a query for 'Standards'.
        ///
        /// Compound identifiers are kept whole *and* split, because both spellings get searched:
        /// 'ListUsers' yields listuser + list + user, 'Identity.User.ReadWrite' the whole string
        /// plus its parts. Without the split a search for 'user permissions' misses a page that
        /// only writes the role name; without the whole form, an exact search for the role name
        /// ranks no better than one for 'user'.
        /// </summary>
        public static string[] Tokenize(string? text)
        {
            if (string.IsNullOrWhiteSpace(text)) return Array.Empty<string>();

            var tokens = new List<string>();
            int i = 0;
            int length = text!.Length;

            while (i < length)
            {
                // Scan one raw word: letters, digits, and the identifier punctuation we keep.
                while (i < length && !IsWordChar(text[i])) i++;
                int start = i;
                while (i < length && IsWordChar(text[i])) i++;
                if (i == start) continue;

                var raw = text.Substring(start, i - start).Trim('.', '-', '_');
                if (raw.Length < 2) continue;

                bool compound = false;
                bool hasLowerUpper = false;
                for (int k = 0; k < raw.Length; k++)
                {
                    char c = raw[k];
                    if (c == '.' || c == '-' || c == '_') compound = true;
                    if (k > 0 && char.IsUpper(c) && char.IsLower(raw[k - 1])) hasLowerUpper = true;
                }

                var whole = raw.ToLowerInvariant();
                AddStemmed(tokens, whole);

                if (!compound && !hasLowerUpper) continue;

                // Split camelCase, then on the identifier punctuation.
                var spaced = new StringBuilder(raw.Length + 8);
                for (int k = 0; k < raw.Length; k++)
                {
                    char c = raw[k];
                    if (k > 0 && char.IsUpper(c) && (char.IsLower(raw[k - 1]) || char.IsDigit(raw[k - 1])))
                        spaced.Append(' ');
                    spaced.Append(c == '.' || c == '-' || c == '_' ? ' ' : c);
                }

                foreach (var part in spaced.ToString().Split(' ', StringSplitOptions.RemoveEmptyEntries))
                {
                    if (part.Length < 2) continue;
                    var lower = part.ToLowerInvariant();
                    if (lower == whole) continue;
                    AddStemmed(tokens, lower);
                }
            }

            return tokens.ToArray();
        }

        private static bool IsWordChar(char c) =>
            char.IsLetterOrDigit(c) || c == '.' || c == '-' || c == '_';

        private static void AddStemmed(List<string> tokens, string lower)
        {
            var stem = Stem(lower);
            if (!StopWords.Contains(stem)) tokens.Add(stem);
        }

        /// <summary>
        /// Light stemming - plural 's'/'es' only. An aggressive stemmer conflates CIPP vocabulary
        /// that has to stay distinct, and the corpus is small enough that recall is not the
        /// problem the stemmer would be solving.
        /// </summary>
        public static string Stem(string token)
        {
            // Too short to suffix-strip without destroying the word ('ies' -> '', 'use' -> 'us').
            if (token.Length <= 4) return token;
            if (token.EndsWith("ies", StringComparison.Ordinal))
                return string.Concat(token.AsSpan(0, token.Length - 3), "y");
            if (token.EndsWith("sses", StringComparison.Ordinal) || token.EndsWith("shes", StringComparison.Ordinal)
                || token.EndsWith("ches", StringComparison.Ordinal) || token.EndsWith("xes", StringComparison.Ordinal))
                return token.Substring(0, token.Length - 2);
            if (token.EndsWith("ss", StringComparison.Ordinal)) return token;
            if (token.EndsWith("s", StringComparison.Ordinal)) return token.Substring(0, token.Length - 1);
            return token;
        }

        // ────────────────────────────────── Search ──────────────────────────────────

        /// <summary>
        /// Ranks chunks for a query. <paramref name="synonymTerms"/> come from the caller's
        /// domain expansion map; fuzzy correction is applied here, only for primary terms the
        /// corpus does not contain at all - a term that matched exactly needs no help, and
        /// fuzzing it would drag in neighbours that dilute a perfectly good query.
        /// </summary>
        public static SearchResult Search(string[]? primaryTerms, string[]? synonymTerms,
            string? pathFilter, int limit, int perPageCap = 2)
        {
            var empty = new SearchResult();
            var data = _current;
            if (data == null || data.Chunks.Count == 0) return empty;
            if (limit < 1) limit = 8;

            primaryTerms ??= Array.Empty<string>();
            synonymTerms ??= Array.Empty<string>();

            var allowedPages = ResolvePathFilter(data, pathFilter);
            if (allowedPages != null && allowedPages.Count == 0) return empty;

            var weighted = new Dictionary<string, double>(StringComparer.Ordinal);
            foreach (var term in primaryTerms)
                if (!string.IsNullOrEmpty(term)) weighted[term] = 1.0;

            foreach (var term in synonymTerms)
                if (!string.IsNullOrEmpty(term) && !weighted.ContainsKey(term))
                    weighted[term] = SynonymWeight;

            foreach (var term in primaryTerms)
            {
                if (string.IsNullOrEmpty(term) || data.Postings.ContainsKey(term)) continue;
                foreach (var near in FuzzyMatches(data, term, 3))
                    if (!weighted.ContainsKey(near)) weighted[near] = FuzzyWeight;
            }

            if (weighted.Count == 0) return empty;

            var scores = new Dictionary<int, double>();
            var covered = new Dictionary<int, HashSet<string>>();
            double chunkCount = data.Chunks.Count;

            foreach (var (term, weight) in weighted)
            {
                if (!data.Postings.TryGetValue(term, out var postings)) continue;

                double documentFrequency = postings.Count;
                double idf = Math.Log(1 + (chunkCount - documentFrequency + 0.5) / (documentFrequency + 0.5));

                foreach (var (chunkId, frequency) in postings)
                {
                    if (allowedPages != null && !allowedPages.Contains(data.Chunks[chunkId].PageIndex)) continue;

                    double len = data.Chunks[chunkId].Length;
                    double denominator = frequency + K1 * (1 - B + B * (len / Math.Max(data.AverageLength, 1)));
                    double contribution = weight * idf * (frequency * (K1 + 1) / Math.Max(denominator, 0.0001));

                    scores.TryGetValue(chunkId, out double running);
                    scores[chunkId] = running + contribution;

                    if (!covered.TryGetValue(chunkId, out var set))
                    {
                        set = new HashSet<string>(StringComparer.Ordinal);
                        covered[chunkId] = set;
                    }
                    set.Add(term);
                }
            }

            if (scores.Count == 0)
            {
                return new SearchResult { Suggestions = Suggest(primaryTerms) };
            }

            // Coverage bonus: a chunk hitting three of the query's terms is answering the whole
            // question; one hitting the same term three times is a page that just says it a lot.
            double primaryCount = Math.Max(primaryTerms.Length, 1);
            foreach (var chunkId in scores.Keys.ToArray())
            {
                double coverage = covered[chunkId].Count / primaryCount;
                scores[chunkId] *= 1 + 0.35 * Math.Min(coverage, 1.5);
            }

            var hits = new List<SearchHit>();
            var takenPerPage = new Dictionary<int, int>();

            foreach (var entry in scores.OrderByDescending(e => e.Value))
            {
                if (hits.Count >= limit) break;
                var chunk = data.Chunks[entry.Key];

                // One page should not occupy the whole result set with five of its own sections.
                takenPerPage.TryGetValue(chunk.PageIndex, out int taken);
                if (taken >= perPageCap) continue;
                takenPerPage[chunk.PageIndex] = taken + 1;

                hits.Add(BuildHit(data.Pages[chunk.PageIndex], chunk, Math.Round(entry.Value, 3),
                    primaryTerms.Concat(synonymTerms).ToArray()));
            }

            return new SearchResult { MatchCount = scores.Count, Hits = hits.ToArray() };
        }

        private static HashSet<int>? ResolvePathFilter(IndexData data, string? pathFilter)
        {
            if (string.IsNullOrWhiteSpace(pathFilter)) return null;

            var needle = pathFilter!.Replace('\\', '/').Trim().Trim('/').ToLowerInvariant();
            var allowed = new HashSet<int>();

            for (int i = 0; i < data.Pages.Count; i++)
            {
                var page = data.Pages[i];
                var slug = page.Slug.ToLowerInvariant();
                var appPath = (page.AppPath ?? "").Trim('/').ToLowerInvariant();

                if (slug == needle || slug.StartsWith(needle + "/", StringComparison.Ordinal)
                    || slug.EndsWith("/" + needle, StringComparison.Ordinal)
                    || (appPath.Length > 0 && (appPath == needle
                        || appPath.StartsWith(needle + "/", StringComparison.Ordinal))))
                {
                    allowed.Add(i);
                }
            }
            return allowed;
        }

        /// <summary>Pages matching a path, for a path-only query with no keywords.</summary>
        public static SearchResult ByPath(string pathFilter, int limit)
        {
            var data = _current;
            if (data == null) return new SearchResult();

            var allowed = ResolvePathFilter(data, pathFilter);
            if (allowed == null || allowed.Count == 0) return new SearchResult();

            var hits = new List<SearchHit>();
            // Shortest slug first: the section index is a better first answer than a leaf page.
            foreach (var pageIndex in allowed.OrderBy(p => data.Pages[p].Slug.Length).Take(limit))
            {
                var intro = data.Chunks.FirstOrDefault(c => c.PageIndex == pageIndex)
                            ?? new ChunkRecord { PageIndex = pageIndex };
                hits.Add(BuildHit(data.Pages[pageIndex], intro, 0, Array.Empty<string>()));
            }
            return new SearchResult { MatchCount = allowed.Count, Hits = hits.ToArray() };
        }

        private static SearchHit BuildHit(PageRecord page, ChunkRecord chunk, double score, string[] terms)
        {
            var fragment = string.IsNullOrEmpty(chunk.Anchor) ? "" : "#" + chunk.Anchor;
            return new SearchHit
            {
                Title = page.Title,
                Section = string.IsNullOrEmpty(chunk.Heading) ? null : chunk.Heading,
                Path = page.RelativePath,
                Excerpt = Excerpt(chunk.Text, terms),
                DocsUrl = page.DocsUrl == null ? null : page.DocsUrl + fragment,
                GitHubUrl = page.GitHubUrl + fragment,
                AppPath = page.AppPath,
                Breadcrumb = page.Breadcrumb,
                Published = page.Published,
                Score = score
            };
        }

        // ─────────────────────────────── Fuzzy matching ───────────────────────────────

        private static List<string> FuzzyMatches(IndexData data, string token, int maxResults)
        {
            var results = new List<(string Term, double Distance, int Frequency)>();
            if (token.Length < 4) return new List<string>();

            int budget = token.Length >= 7 ? 2 : 1;
            char first = token[0];

            foreach (var candidate in data.Postings.Keys)
            {
                if (Math.Abs(candidate.Length - token.Length) > budget)
                {
                    // A longer vocabulary term the query prefixes is still a good lead:
                    // 'conditional' should reach 'conditionalaccess'.
                    if (candidate.Length > token.Length && candidate.StartsWith(token, StringComparison.Ordinal))
                        results.Add((candidate, 0.5, data.Postings[candidate].Count));
                    continue;
                }
                if (candidate.Length == 0 || candidate[0] != first) continue;

                int distance = EditDistance(token, candidate, budget);
                if (distance <= budget) results.Add((candidate, distance, data.Postings[candidate].Count));
            }

            return results
                .OrderBy(r => r.Distance)
                .ThenByDescending(r => r.Frequency)
                .Take(maxResults)
                .Select(r => r.Term)
                .ToList();
        }

        /// <summary>Levenshtein distance, abandoning the row once it exceeds the ceiling.</summary>
        public static int EditDistance(string first, string second, int ceiling = 2)
        {
            if (first.Length == 0) return second.Length;
            if (second.Length == 0) return first.Length;

            var previous = new int[second.Length + 1];
            var current = new int[second.Length + 1];
            for (int j = 0; j <= second.Length; j++) previous[j] = j;

            for (int i = 1; i <= first.Length; i++)
            {
                current[0] = i;
                int rowMinimum = current[0];
                for (int j = 1; j <= second.Length; j++)
                {
                    int cost = first[i - 1] == second[j - 1] ? 0 : 1;
                    current[j] = Math.Min(Math.Min(current[j - 1] + 1, previous[j] + 1), previous[j - 1] + cost);
                    if (current[j] < rowMinimum) rowMinimum = current[j];
                }
                if (rowMinimum > ceiling) return ceiling + 1;
                (previous, current) = (current, previous);
            }
            return previous[second.Length];
        }

        /// <summary>Closest real vocabulary terms, for the "did you mean" path on a zero-result query.</summary>
        public static string[] Suggest(string[] terms, int maxResults = 5)
        {
            var data = _current;
            if (data == null) return Array.Empty<string>();

            var suggestions = new List<string>();
            foreach (var term in terms)
            {
                foreach (var near in FuzzyMatches(data, term, 2))
                {
                    if (suggestions.Count >= maxResults) break;
                    if (!suggestions.Contains(near)) suggestions.Add(near);
                }
            }
            return suggestions.ToArray();
        }

        // ─────────────────────────────────── Pages ───────────────────────────────────

        /// <summary>Fetches a page by repo-relative path, slug or app route, for GetDoc.</summary>
        public static PageRecord? FindPage(string pathOrSlug)
        {
            var data = _current;
            if (data == null || string.IsNullOrWhiteSpace(pathOrSlug)) return null;

            var needle = pathOrSlug.Replace('\\', '/').Trim().Trim('/').ToLowerInvariant();
            var withoutExtension = needle.EndsWith(".md", StringComparison.Ordinal)
                ? needle.Substring(0, needle.Length - 3) : needle;

            PageRecord? bySlug = null, byApp = null, bySuffix = null;
            foreach (var page in data.Pages)
            {
                var relative = page.RelativePath.ToLowerInvariant();
                if (relative == needle || relative == needle + ".md") return page;

                var slug = page.Slug.ToLowerInvariant();
                if (slug == withoutExtension) bySlug ??= page;
                if ((page.AppPath ?? "").Trim('/').ToLowerInvariant() == withoutExtension) byApp ??= page;
                if (relative.EndsWith("/" + withoutExtension + ".md", StringComparison.Ordinal)) bySuffix ??= page;
            }
            return bySlug ?? byApp ?? bySuffix;
        }

        /// <summary>The full text of a page, reassembled from its chunks with headings restored.</summary>
        public static string GetPageText(string relativePath)
        {
            var data = _current;
            if (data == null) return "";

            var builder = new StringBuilder();
            for (int i = 0; i < data.Pages.Count; i++)
            {
                if (!string.Equals(data.Pages[i].RelativePath, relativePath, StringComparison.OrdinalIgnoreCase))
                    continue;

                builder.Append("# ").AppendLine(data.Pages[i].Title);
                foreach (var chunk in data.Chunks.Where(c => c.PageIndex == i))
                {
                    if (!string.IsNullOrEmpty(chunk.Heading))
                        builder.AppendLine().Append("## ").AppendLine(chunk.Heading);
                    if (!string.IsNullOrEmpty(chunk.Text)) builder.AppendLine(chunk.Text);
                }
                break;
            }
            return builder.ToString().Trim();
        }

        public static PageRecord[] GetPages() => _current?.Pages.ToArray() ?? Array.Empty<PageRecord>();

        // ────────────────────────────────── Excerpts ──────────────────────────────────

        /// <summary>
        /// A readable window of the chunk centred on the query's terms, so the caller can judge
        /// relevance without a second call. Falls back to the opening sentence, which is a fair
        /// summary of a section.
        /// </summary>
        private static string Excerpt(string text, string[] terms, int width = 320)
        {
            if (string.IsNullOrWhiteSpace(text)) return "";

            var flat = System.Text.RegularExpressions.Regex.Replace(text, @"\s+", " ").Trim();
            if (flat.Length <= width) return flat;

            int best = 0;
            if (terms.Length > 0)
            {
                var lower = flat.ToLowerInvariant();
                int bestHits = -1;
                // Sampled window starts, not every offset: the excerpt only needs to be
                // representative, and this keeps a 25 KB section cheap to summarise.
                for (int start = 0; start < flat.Length - 1; start += 40)
                {
                    int span = Math.Min(width, lower.Length - start);
                    var slice = lower.Substring(start, span);
                    int hits = terms.Count(t => t.Length > 0 && slice.Contains(t, StringComparison.Ordinal));
                    if (hits > bestHits) { bestHits = hits; best = start; }
                }
                if (bestHits <= 0) best = 0;
            }

            if (best > 0)
            {
                int space = flat.LastIndexOf(' ', Math.Min(best, flat.Length - 1));
                if (space > 0) best = space + 1;
            }

            var excerpt = flat.Substring(best, Math.Min(width, flat.Length - best)).Trim();
            return (best > 0 ? "..." : "") + excerpt + (best + width < flat.Length ? "..." : "");
        }
    }
}
