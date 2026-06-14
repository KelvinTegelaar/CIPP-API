# Pester tests for Read-CippMimeMessage
# Verifies common quarantine EML parsing cases used by the details fallback path

Describe 'Read-CippMimeMessage' {
    BeforeAll {
        $RepoRoot = Split-Path -Parent $PSScriptRoot
        $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Read-CippMimeMessage.ps1'

        . $FunctionPath

        function Get-TestSha256 {
            param([byte[]]$Bytes)

            $Sha256 = [System.Security.Cryptography.SHA256]::Create()
            try {
                ([BitConverter]::ToString($Sha256.ComputeHash($Bytes)) -replace '-', '').ToLowerInvariant()
            } finally {
                $Sha256.Dispose()
            }
        }
    }

    It 'extracts a base64 attachment with file name, size, and SHA256' {
        $AttachmentBytes = [System.Text.Encoding]::UTF8.GetBytes('Attachment body')
        $AttachmentBase64 = [Convert]::ToBase64String($AttachmentBytes)
        $ExpectedHash = Get-TestSha256 -Bytes $AttachmentBytes
        $Eml = @"
From: Sender <sender@contoso.com>
To: Recipient <recipient@contoso.com>
Subject: Attachment test
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="mix"

--mix
Content-Type: text/plain; charset="utf-8"

See https://example.com/path.
--mix
Content-Type: application/pdf; name="invoice.pdf"
Content-Disposition: attachment; filename="invoice.pdf"
Content-Transfer-Encoding: base64

$AttachmentBase64
--mix--
"@

        $Result = Read-CippMimeMessage -Message $Eml

        $Result.attachments.Count | Should -Be 1
        $Result.attachments[0].fileName | Should -Be 'invoice.pdf'
        $Result.attachments[0].contentType | Should -Be 'application/pdf'
        $Result.attachments[0].fileSize | Should -Be $AttachmentBytes.Length
        $Result.attachments[0].sha256 | Should -Be $ExpectedHash
        $Result.attachments[0].threatType | Should -BeNullOrEmpty
        $Result.urls.url | Should -Contain 'https://example.com/path'
    }

    It 'extracts URLs from quoted-printable HTML bodies' {
        $Eml = @'
From: Sender <sender@contoso.com>
To: Recipient <recipient@contoso.com>
Subject: URL test
MIME-Version: 1.0
Content-Type: text/html; charset="utf-8"
Content-Transfer-Encoding: quoted-printable

<html><body><a href=3D"https://contoso.example/login?x=3D1">Open</a>
Bare link https://tail.example/path.</body></html>
'@

        $Result = Read-CippMimeMessage -Message $Eml

        $Result.urls.Count | Should -Be 2
        $Result.urls.url | Should -Contain 'https://contoso.example/login?x=1'
        $Result.urls.url | Should -Contain 'https://tail.example/path'
        $Result.urls[0].threatType | Should -BeNullOrEmpty
        $Result.urls[0].detectionMethod | Should -BeNullOrEmpty
    }

    It 'descends nested multiparts and decodes extended attachment file names' {
        $AttachmentBytes = [System.Text.Encoding]::UTF8.GetBytes('nested attachment')
        $AttachmentBase64 = [Convert]::ToBase64String($AttachmentBytes)
        $Eml = @"
From: Sender <sender@contoso.com>
To: Recipient <recipient@contoso.com>
Subject: Nested test
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="outer"

--outer
Content-Type: multipart/alternative; boundary="inner"

--inner
Content-Type: text/plain; charset="utf-8"

Plain link https://nested.example/plain
--inner
Content-Type: text/html; charset="utf-8"

<a href="https://nested.example/html">HTML link</a>
--inner--
--outer
Content-Type: application/octet-stream
Content-Disposition: attachment; filename*=utf-8''report%20one.txt
Content-Transfer-Encoding: base64

$AttachmentBase64
--outer--
"@

        $Result = Read-CippMimeMessage -Message $Eml

        $Result.urls.url | Should -Contain 'https://nested.example/plain'
        $Result.urls.url | Should -Contain 'https://nested.example/html'
        $Result.attachments.Count | Should -Be 1
        $Result.attachments[0].fileName | Should -Be 'report one.txt'
        $Result.attachments[0].fileSize | Should -Be $AttachmentBytes.Length
    }
}
