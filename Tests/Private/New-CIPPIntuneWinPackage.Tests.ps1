# Pester tests for New-CIPPIntuneWinPackage: the uploaded installer becomes an .intunewin payload that decrypts
# and unzips back to the installer, with the metadata Intune checks on commit.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function New-CIPPAzStorageRequest { param($Service, $Resource, $Method, $QueryParams, $Headers, $ContentType, $Body) }
    function Write-LogMessage { param($API, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/New-CIPPIntuneWinPackage.ps1')
    Add-Type -AssemblyName System.IO.Compression
    $script:PackageId = '6f1c2a3b-1111-2222-3333-444455556666'
}

Describe 'New-CIPPIntuneWinPackage' {
    BeforeEach {
        $script:Blocks = @{}
        $script:Deleted = [System.Collections.Generic.List[string]]::new()
        $script:Packaged = $null
        # In-memory blob storage: range reads of $script:Installer, block writes, packaged.json and deletes.
        Mock New-CIPPAzStorageRequest {
            if ($Method -eq 'DELETE') { $script:Deleted.Add($Resource); return }
            if ($QueryParams.comp -eq 'block') { $script:Blocks[[int][Text.Encoding]::ASCII.GetString([Convert]::FromBase64String($QueryParams.blockid))] = [byte[]]$Body.Clone(); return }
            if ($Resource -like '*/packaged.json') { $script:Packaged = $Body | ConvertFrom-Json; return }
            $Start, $End = [int64[]](($Headers.Range -replace 'bytes=') -split '-')
            $End = [Math]::Min($End, $script:Installer.Length - 1)
            $Slice = [byte[]]::new($End - $Start + 1); [Array]::Copy($script:Installer, $Start, $Slice, 0, $Slice.Length)
            [pscustomobject]@{ Bytes = $Slice; Length = $Slice.Length; Headers = @{ 'Content-Range' = "bytes $Start-$End/$($script:Installer.Length)" } }
        }
    }

    It 'packages <Case> into a payload that verifies and unzips to the installer' -ForEach @(
        @{ Case = 'an installer spanning several blocks'; Size = 20MB }
        @{ Case = 'a small installer'; Size = 1000 }
    ) {
        $script:Installer = [byte[]]::new($Size); [System.Random]::new(7).NextBytes($script:Installer)

        New-CIPPIntuneWinPackage -PackageId $script:PackageId -SetupFile 'setup.exe'

        $Info = $script:Packaged.metadata.EncryptionInfo
        $script:Packaged.blockCount | Should -Be $script:Blocks.Count
        $Stream = [System.IO.MemoryStream]::new()
        foreach ($i in 0..($script:Blocks.Count - 1)) { $Stream.Write($script:Blocks[$i], 0, $script:Blocks[$i].Length) }
        $Payload = $Stream.ToArray()
        $script:Packaged.metadata.EncryptedSize | Should -Be $Payload.Length
        $Body = [byte[]]::new($Payload.Length - 32); [Array]::Copy($Payload, 32, $Body, 0, $Body.Length)
        [Convert]::ToBase64String($Payload, 0, 32) | Should -Be $Info.Mac
        [Convert]::ToBase64String([Security.Cryptography.HMACSHA256]::HashData([Convert]::FromBase64String($Info.MacKey), $Body)) | Should -Be $Info.Mac
        $Aes = [Security.Cryptography.Aes]::Create(); $Aes.Key = [Convert]::FromBase64String($Info.EncryptionKey)
        $Cipher = [byte[]]::new($Body.Length - 16); [Array]::Copy($Body, 16, $Cipher, 0, $Cipher.Length)
        $Iv = [byte[]]::new(16); [Array]::Copy($Body, 0, $Iv, 0, 16)
        $Iv | Should -Be ([Convert]::FromBase64String($Info.InitializationVector))
        $Plain = $Aes.DecryptCbc($Cipher, $Iv)
        $Plain.Length | Should -Be $script:Packaged.metadata.UnencryptedContentSize
        [Convert]::ToBase64String([Security.Cryptography.SHA256]::HashData($Plain)) | Should -Be $Info.FileDigest
        $Zip = [IO.Compression.ZipArchive]::new([IO.MemoryStream]::new($Plain))
        $Zip.Entries.FullName | Should -Be @('setup.exe')
        $Unzipped = [IO.MemoryStream]::new(); $Zip.Entries[0].Open().CopyTo($Unzipped)
        [Convert]::ToHexString($Unzipped.ToArray()) | Should -Be ([Convert]::ToHexString($script:Installer))
        $script:Packaged.metadata.SetupFile | Should -Be 'setup.exe'
        $script:Deleted | Should -Contain "app-packages/$($script:PackageId)/installer"
    }

    It 'records the error and deletes the installer when packaging fails' {
        Mock New-CIPPAzStorageRequest {
            if ($Method -eq 'DELETE') { $script:Deleted.Add($Resource); return }
            if ($Resource -like '*/packaged.json') { $script:Packaged = $Body | ConvertFrom-Json; return }
            throw 'Status 503'
        }

        New-CIPPIntuneWinPackage -PackageId $script:PackageId -SetupFile 'setup.msi'

        $script:Packaged.error | Should -Match 'setup\.msi.*503'
        $script:Packaged.blockCount | Should -BeNullOrEmpty
        $script:Deleted | Should -Contain "app-packages/$($script:PackageId)/installer"
    }
}
