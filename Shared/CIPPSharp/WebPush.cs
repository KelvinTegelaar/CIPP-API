#nullable enable
using System;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace CIPP
{
    // =====================================================================
    // WebPush
    // =====================================================================
    // Web Push (RFC 8030) delivery with VAPID (RFC 8292) and aes128gcm
    // payload encryption (RFC 8291 / RFC 8188), on .NET's in-box crypto.
    // Kept in C# rather than PowerShell because the whole thing is byte
    // arrays and HKDF labels, which PowerShell makes fragile.
    //
    // PowerShell: [CIPP.WebPush]::GenerateVapidKeys() once per instance,
    // then [CIPP.WebPush]::Send(...) per subscription.
    // =====================================================================
    public sealed class VapidKeys
    {
        public string PublicKey  { get; init; } = string.Empty; // base64url, 65-byte uncompressed P-256 point
        public string PrivateKey { get; init; } = string.Empty; // base64url, 32-byte scalar
    }

    public sealed class WebPushResult
    {
        public int    StatusCode { get; init; }
        public bool   IsSuccess  { get; init; }
        public string Content    { get; init; } = string.Empty;
        // 404/410 from the push service means the subscription is dead and should be pruned.
        public bool   IsGone => StatusCode == 404 || StatusCode == 410;
    }

    public static class WebPush
    {
        private const int RecordSize = 4096;
        private static readonly HttpClient Client = new HttpClient(new SocketsHttpHandler
        {
            PooledConnectionLifetime = TimeSpan.FromMinutes(5),
        })
        { Timeout = TimeSpan.FromSeconds(30) };

        public static VapidKeys GenerateVapidKeys()
        {
            using var ecdsa = ECDsa.Create(ECCurve.NamedCurves.nistP256);
            var p = ecdsa.ExportParameters(true);
            return new VapidKeys
            {
                PublicKey  = Base64Url(UncompressedPoint(p.Q)),
                PrivateKey = Base64Url(p.D!),
            };
        }

        public static WebPushResult Send(
            string endpoint, string p256dh, string auth, string payload,
            string vapidPublicKey, string vapidPrivateKey, string subject, int ttlSeconds = 86400)
        {
            var body = Encrypt(payload, p256dh, auth);
            var jwt  = CreateVapidJwt(new Uri(endpoint), vapidPublicKey, vapidPrivateKey, subject);

            using var request = new HttpRequestMessage(HttpMethod.Post, endpoint);
            request.Headers.TryAddWithoutValidation("Authorization", $"vapid t={jwt}, k={vapidPublicKey}");
            request.Headers.TryAddWithoutValidation("TTL", ttlSeconds.ToString());
            request.Headers.TryAddWithoutValidation("Urgency", "normal");
            request.Content = new ByteArrayContent(body);
            request.Content.Headers.ContentType = new MediaTypeHeaderValue("application/octet-stream");
            request.Content.Headers.ContentEncoding.Add("aes128gcm");

            using var response = Client.Send(request);
            return new WebPushResult
            {
                StatusCode = (int)response.StatusCode,
                IsSuccess  = response.IsSuccessStatusCode,
                Content    = response.Content.ReadAsStringAsync().GetAwaiter().GetResult(),
            };
        }

        // RFC 8291 §3 + RFC 8188: returns the full aes128gcm body (header || ciphertext || tag).
        public static byte[] Encrypt(string payload, string p256dh, string auth)
        {
            var uaPublic   = FromBase64Url(p256dh);
            var authSecret = FromBase64Url(auth);
            if (uaPublic.Length != 65 || uaPublic[0] != 0x04) throw new ArgumentException("p256dh must be a 65-byte uncompressed P-256 point");
            if (authSecret.Length != 16) throw new ArgumentException("auth must be 16 bytes");

            using var asKey = ECDiffieHellman.Create(ECCurve.NamedCurves.nistP256);
            var asPublic = UncompressedPoint(asKey.ExportParameters(false).Q);
            using var uaKey = ECDiffieHellman.Create(new ECParameters
            {
                Curve = ECCurve.NamedCurves.nistP256,
                Q = new ECPoint { X = uaPublic[1..33], Y = uaPublic[33..65] },
            });
            var ecdhSecret = asKey.DeriveRawSecretAgreement(uaKey.PublicKey);

            var salt = RandomNumberGenerator.GetBytes(16);
            var plaintext = Encoding.UTF8.GetBytes(payload);
            var record = new byte[plaintext.Length + 1];
            plaintext.CopyTo(record, 0);
            record[^1] = 0x02; // last-record delimiter
            var ciphertext = new byte[record.Length];
            var tag = new byte[16];

            var (cek, nonce) = DeriveKeys(ecdhSecret, authSecret, uaPublic, asPublic, salt);
            using (var aes = new AesGcm(cek, 16)) aes.Encrypt(nonce, record, ciphertext, tag);

            // header: salt(16) | rs(4, big-endian) | idlen(1) | keyid(65)
            var header = new byte[16 + 4 + 1 + 65];
            salt.CopyTo(header, 0);
            System.Buffers.Binary.BinaryPrimitives.WriteUInt32BigEndian(header.AsSpan(16, 4), RecordSize);
            header[20] = 65;
            asPublic.CopyTo(header, 21);

            var body = new byte[header.Length + ciphertext.Length + tag.Length];
            header.CopyTo(body, 0);
            ciphertext.CopyTo(body, header.Length);
            tag.CopyTo(body, header.Length + ciphertext.Length);
            return body;
        }

        // Test-side counterpart: decrypt a body produced by Encrypt using the subscriber's private key.
        public static string Decrypt(byte[] body, string uaPrivateKey, string uaPublicKey, string auth)
        {
            var uaPublic   = FromBase64Url(uaPublicKey);
            var authSecret = FromBase64Url(auth);
            var salt = body[0..16];
            var idlen = body[20];
            var asPublic = body[21..(21 + idlen)];
            var cipherAndTag = body[(21 + idlen)..];

            using var uaKey = ECDiffieHellman.Create(new ECParameters
            {
                Curve = ECCurve.NamedCurves.nistP256,
                D = FromBase64Url(uaPrivateKey),
                Q = new ECPoint { X = uaPublic[1..33], Y = uaPublic[33..65] },
            });
            using var asKey = ECDiffieHellman.Create(new ECParameters
            {
                Curve = ECCurve.NamedCurves.nistP256,
                Q = new ECPoint { X = asPublic[1..33], Y = asPublic[33..65] },
            });
            var ecdhSecret = uaKey.DeriveRawSecretAgreement(asKey.PublicKey);
            var (cek, nonce) = DeriveKeys(ecdhSecret, authSecret, uaPublic, asPublic, salt);

            var ciphertext = cipherAndTag[..^16];
            var tag = cipherAndTag[^16..];
            var record = new byte[ciphertext.Length];
            using (var aes = new AesGcm(cek, 16)) aes.Decrypt(nonce, ciphertext, tag, record);
            if (record[^1] != 0x02) throw new CryptographicException("missing last-record delimiter");
            return Encoding.UTF8.GetString(record, 0, record.Length - 1);
        }

        private static (byte[] cek, byte[] nonce) DeriveKeys(byte[] ecdhSecret, byte[] authSecret, byte[] uaPublic, byte[] asPublic, byte[] salt)
        {
            var keyInfo = Concat(Encoding.ASCII.GetBytes("WebPush: info\0"), uaPublic, asPublic);
            var ikm = HKDF.DeriveKey(HashAlgorithmName.SHA256, ecdhSecret, 32, authSecret, keyInfo);
            var cek = HKDF.DeriveKey(HashAlgorithmName.SHA256, ikm, 16, salt, Encoding.ASCII.GetBytes("Content-Encoding: aes128gcm\0"));
            var nonce = HKDF.DeriveKey(HashAlgorithmName.SHA256, ikm, 12, salt, Encoding.ASCII.GetBytes("Content-Encoding: nonce\0"));
            return (cek, nonce);
        }

        public static string CreateVapidJwt(Uri endpoint, string vapidPublicKey, string vapidPrivateKey, string subject)
        {
            var pub = FromBase64Url(vapidPublicKey);
            using var ecdsa = ECDsa.Create(new ECParameters
            {
                Curve = ECCurve.NamedCurves.nistP256,
                D = FromBase64Url(vapidPrivateKey),
                Q = new ECPoint { X = pub[1..33], Y = pub[33..65] },
            });
            var header = Base64Url(Encoding.UTF8.GetBytes("{\"typ\":\"JWT\",\"alg\":\"ES256\"}"));
            var claims = Base64Url(JsonSerializer.SerializeToUtf8Bytes(new
            {
                aud = endpoint.GetLeftPart(UriPartial.Authority),
                exp = DateTimeOffset.UtcNow.AddHours(12).ToUnixTimeSeconds(),
                sub = subject,
            }));
            var signingInput = Encoding.ASCII.GetBytes($"{header}.{claims}");
            var signature = ecdsa.SignData(signingInput, HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation);
            return $"{header}.{claims}.{Base64Url(signature)}";
        }

        public static bool VerifyVapidJwt(string jwt, string vapidPublicKey)
        {
            var parts = jwt.Split('.');
            if (parts.Length != 3) return false;
            var pub = FromBase64Url(vapidPublicKey);
            using var ecdsa = ECDsa.Create(new ECParameters
            {
                Curve = ECCurve.NamedCurves.nistP256,
                Q = new ECPoint { X = pub[1..33], Y = pub[33..65] },
            });
            return ecdsa.VerifyData(Encoding.ASCII.GetBytes($"{parts[0]}.{parts[1]}"), FromBase64Url(parts[2]),
                HashAlgorithmName.SHA256, DSASignatureFormat.IeeeP1363FixedFieldConcatenation);
        }

        private static byte[] UncompressedPoint(ECPoint q) => Concat(new byte[] { 0x04 }, q.X!, q.Y!);

        private static byte[] Concat(params byte[][] parts)
        {
            var total = 0;
            foreach (var p in parts) total += p.Length;
            var result = new byte[total];
            var offset = 0;
            foreach (var p in parts) { p.CopyTo(result, offset); offset += p.Length; }
            return result;
        }

        public static string Base64Url(byte[] data) =>
            Convert.ToBase64String(data).TrimEnd('=').Replace('+', '-').Replace('/', '_');

        public static byte[] FromBase64Url(string s)
        {
            var padded = s.Replace('-', '+').Replace('_', '/');
            padded = padded.PadRight(padded.Length + (4 - padded.Length % 4) % 4, '=');
            return Convert.FromBase64String(padded);
        }
    }
}
