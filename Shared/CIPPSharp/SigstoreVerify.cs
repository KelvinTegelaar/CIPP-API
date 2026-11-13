#nullable enable
using System;
using System.Formats.Asn1;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Text.Json;

namespace CIPP
{
    // =====================================================================
    // SigstoreVerify
    // =====================================================================
    // Offline verification of a Sigstore bundle (v0.3, DSSE envelope) as
    // produced by actions/attest-build-provenance for a container image.
    // Checks the DSSE signature against the Fulcio leaf, the leaf against
    // the supplied trust chain, the OIDC issuer, and the in-toto subject
    // digest. Identity policy (which repo/workflow is acceptable) is left
    // to the caller via the parsed SAN fields.
    //
    // ponytail: trust root is the pinned Sigstore public-good chain passed in
    // by the caller, and the Rekor entry / signed timestamp is not checked;
    // upgrade path is fetching the Sigstore TUF trusted root and verifying
    // tlog inclusion so the leaf's 10-minute validity window can be enforced.
    // =====================================================================
    public sealed class SigstoreVerifyResult
    {
        public bool   Verified   { get; init; }
        // Parse | Signature | Chain | Issuer | Digest | Identity | Ok
        public string Stage      { get; init; } = string.Empty;
        public string Reason     { get; init; } = string.Empty;
        public string Identity   { get; init; } = string.Empty; // SAN URI
        public string Repository { get; init; } = string.Empty; // owner/repo
        public string Workflow   { get; init; } = string.Empty; // .github/workflows/x.yml
        public string Ref        { get; init; } = string.Empty;
        public string Commit     { get; init; } = string.Empty;
        public string LeafIssuer { get; init; } = string.Empty;
    }

    public static class SigstoreVerify
    {
        private const string GitHubIssuer = "https://token.actions.githubusercontent.com";
        private const string OidIssuer = "1.3.6.1.4.1.57264.1.1";            // raw string
        private const string OidSourceDigest = "1.3.6.1.4.1.57264.1.13";     // DER UTF8String
        private const string OidCodeSigning = "1.3.6.1.5.5.7.3.3";

        public static SigstoreVerifyResult Verify(string bundleJson, string expectedDigestHex, string trustChainPem)
        {
            expectedDigestHex ??= string.Empty;
            X509Certificate2 leaf;
            string payloadType;
            byte[] payload, sig;
            try
            {
                using var doc = JsonDocument.Parse(bundleJson);
                var root = doc.RootElement;
                var raw = root.GetProperty("verificationMaterial").GetProperty("certificate").GetProperty("rawBytes").GetString();
                var env = root.GetProperty("dsseEnvelope");
                payloadType = env.GetProperty("payloadType").GetString() ?? string.Empty;
                payload = Convert.FromBase64String(env.GetProperty("payload").GetString() ?? string.Empty);
                sig = Convert.FromBase64String(env.GetProperty("signatures")[0].GetProperty("sig").GetString() ?? string.Empty);
                leaf = new X509Certificate2(Convert.FromBase64String(raw ?? string.Empty));
            }
            catch (Exception ex)
            {
                return Fail("Parse", $"Bundle could not be parsed: {ex.Message}");
            }

            using (leaf)
            {
                var issuerDn = leaf.Issuer;

                // DSSE pre-authentication encoding: lengths are ASCII decimal byte counts.
                var typeBytes = Encoding.UTF8.GetBytes(payloadType);
                var header = Encoding.UTF8.GetBytes($"DSSEv1 {typeBytes.Length} {payloadType} {payload.Length} ");
                var pae = new byte[header.Length + payload.Length];
                header.CopyTo(pae, 0);
                payload.CopyTo(pae, header.Length);
                bool sigOk;
                try
                {
                    using var key = leaf.GetECDsaPublicKey();
                    sigOk = key != null && key.VerifyData(pae, sig, HashAlgorithmName.SHA256, DSASignatureFormat.Rfc3279DerSequence);
                }
                catch (CryptographicException) { sigOk = false; }
                if (!sigOk)
                    return Fail("Signature", "DSSE signature does not verify against the signing certificate", issuerDn);

                using (var chain = new X509Chain())
                {
                    chain.ChainPolicy.TrustMode = X509ChainTrustMode.CustomRootTrust;
                    chain.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;
                    // Fulcio leaves live 10 minutes; validity is anchored by the signing time, not now.
                    chain.ChainPolicy.VerificationFlags = X509VerificationFlags.IgnoreNotTimeValid;
                    chain.ChainPolicy.ApplicationPolicy.Add(new Oid(OidCodeSigning));
                    var trust = new X509Certificate2Collection();
                    trust.ImportFromPem(trustChainPem);
                    foreach (var c in trust)
                    {
                        // Only self-signed certs are anchors; intermediates just help build the path.
                        if (c.SubjectName.RawData.AsSpan().SequenceEqual(c.IssuerName.RawData)) chain.ChainPolicy.CustomTrustStore.Add(c);
                        else chain.ChainPolicy.ExtraStore.Add(c);
                    }
                    if (chain.ChainPolicy.CustomTrustStore.Count == 0)
                        return Fail("Chain", "Trust chain contains no root certificate", issuerDn);
                    if (!chain.Build(leaf))
                    {
                        var status = string.Join("; ", Array.ConvertAll(chain.ChainStatus, s => s.StatusInformation.Trim()));
                        return Fail("Chain", $"Signing certificate does not chain to the trusted root: {status}", issuerDn);
                    }
                }

                var issuer = leaf.Extensions[OidIssuer] is { } ext ? Encoding.UTF8.GetString(ext.RawData) : string.Empty;
                if (issuer != GitHubIssuer)
                    return Fail("Issuer", $"Certificate OIDC issuer is '{issuer}', expected {GitHubIssuer}", issuerDn);

                string subjectDigest;
                try
                {
                    using var stmt = JsonDocument.Parse(payload);
                    subjectDigest = stmt.RootElement.GetProperty("subject")[0].GetProperty("digest").GetProperty("sha256").GetString() ?? string.Empty;
                }
                catch (Exception ex)
                {
                    return Fail("Parse", $"Attestation statement could not be parsed: {ex.Message}", issuerDn);
                }
                var expected = expectedDigestHex.StartsWith("sha256:", StringComparison.OrdinalIgnoreCase) ? expectedDigestHex[7..] : expectedDigestHex;
                if (!string.Equals(subjectDigest, expected, StringComparison.OrdinalIgnoreCase))
                    return Fail("Digest", $"Attestation subject digest {subjectDigest} does not match image digest {expected}", issuerDn);

                var san = ReadSanUri(leaf);
                // https://github.com/<owner>/<repo>/<workflow path>@<ref>
                var at = san.LastIndexOf('@');
                var parts = san.StartsWith("https://github.com/", StringComparison.Ordinal) && at > 0
                    ? san[19..at].Split('/', 3)
                    : Array.Empty<string>();
                if (parts.Length != 3)
                    return Fail("Identity", $"Certificate identity '{san}' is not a GitHub workflow URI", issuerDn);

                string commit = string.Empty;
                if (leaf.Extensions[OidSourceDigest] is { } c13)
                {
                    try { commit = new AsnReader(c13.RawData, AsnEncodingRules.DER).ReadCharacterString(UniversalTagNumber.UTF8String); }
                    catch (AsnContentException) { }
                }

                return new SigstoreVerifyResult
                {
                    Verified = true,
                    Stage = "Ok",
                    Reason = "Verified",
                    Identity = san,
                    Repository = $"{parts[0]}/{parts[1]}",
                    Workflow = parts[2],
                    Ref = san[(at + 1)..],
                    Commit = commit,
                    LeafIssuer = issuerDn,
                };
            }
        }

        private static string ReadSanUri(X509Certificate2 cert)
        {
            var ext = cert.Extensions["2.5.29.17"];
            if (ext == null) return string.Empty;
            try
            {
                var seq = new AsnReader(ext.RawData, AsnEncodingRules.DER).ReadSequence();
                var uriTag = new Asn1Tag(TagClass.ContextSpecific, 6);
                while (seq.HasData)
                {
                    if (seq.PeekTag() == uriTag) return seq.ReadCharacterString(UniversalTagNumber.IA5String, uriTag);
                    seq.ReadEncodedValue();
                }
            }
            catch (AsnContentException) { }
            return string.Empty;
        }

        private static SigstoreVerifyResult Fail(string stage, string reason, string leafIssuer = "") =>
            new SigstoreVerifyResult { Verified = false, Stage = stage, Reason = reason, LeafIssuer = leafIssuer };
    }
}
