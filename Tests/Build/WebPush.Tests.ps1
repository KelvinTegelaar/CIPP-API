# Pester tests for CIPP.WebPush in CIPPSharp.
#
# Pins the RFC 8291 payload encryption and the RFC 8292 VAPID token against .NET's own
# primitives: a body encrypted for a subscriber decrypts with that subscriber's private key
# and nobody else's, and the VAPID JWT verifies against the instance public key only.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Dll = Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll'
    if (-not (Test-Path $Dll)) { throw "CIPPSharp.dll not built at $Dll" }
    if (-not ('CIPP.WebPush' -as [type])) { Add-Type -Path $Dll }
}

Describe 'CIPP.WebPush' {
    It 'generates a P-256 key pair in base64url with a 65-byte uncompressed public point' {
        $Keys = [CIPP.WebPush]::GenerateVapidKeys()
        $Keys.PublicKey | Should -Match '^[A-Za-z0-9_-]+$'
        [CIPP.WebPush]::FromBase64Url($Keys.PublicKey).Length | Should -Be 65
        [CIPP.WebPush]::FromBase64Url($Keys.PrivateKey).Length | Should -Be 32
    }

    It 'encrypts a payload that only the subscriber can decrypt' {
        # A browser subscription is the same key shape as a VAPID pair.
        $Subscriber = [CIPP.WebPush]::GenerateVapidKeys()
        $Auth = [CIPP.WebPush]::Base64Url([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(16))
        $Payload = '{"title":"CIPP","body":"ünïcode ✓"}'

        $Body = [CIPP.WebPush]::Encrypt($Payload, $Subscriber.PublicKey, $Auth)
        # aes128gcm header: salt(16) rs(4) idlen(1)=65 keyid(65)
        $Body[20] | Should -Be 65
        [CIPP.WebPush]::Decrypt($Body, $Subscriber.PrivateKey, $Subscriber.PublicKey, $Auth) | Should -Be $Payload

        $Other = [CIPP.WebPush]::GenerateVapidKeys()
        { [CIPP.WebPush]::Decrypt($Body, $Other.PrivateKey, $Other.PublicKey, $Auth) } | Should -Throw
    }

    It 'rejects a malformed subscription key' {
        { [CIPP.WebPush]::Encrypt('x', 'AAAA', 'AAAAAAAAAAAAAAAAAAAAAA') } | Should -Throw '*65-byte*'
    }

    It 'signs a VAPID JWT for the push service origin that verifies with the public key only' {
        $Keys = [CIPP.WebPush]::GenerateVapidKeys()
        $Jwt = [CIPP.WebPush]::CreateVapidJwt([uri]'https://fcm.googleapis.com/fcm/send/abc123', $Keys.PublicKey, $Keys.PrivateKey, 'https://cipp.contoso.com')
        $Parts = $Jwt.Split('.')
        $Parts.Count | Should -Be 3
        $Claims = [System.Text.Encoding]::UTF8.GetString([CIPP.WebPush]::FromBase64Url($Parts[1])) | ConvertFrom-Json
        $Claims.aud | Should -Be 'https://fcm.googleapis.com'
        $Claims.sub | Should -Be 'https://cipp.contoso.com'
        [CIPP.WebPush]::VerifyVapidJwt($Jwt, $Keys.PublicKey) | Should -BeTrue
        [CIPP.WebPush]::VerifyVapidJwt($Jwt, ([CIPP.WebPush]::GenerateVapidKeys()).PublicKey) | Should -BeFalse
    }
}
