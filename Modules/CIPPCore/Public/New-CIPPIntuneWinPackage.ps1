function New-CIPPIntuneWinPackage {
    <#
    .SYNOPSIS
        Packages an uploaded .exe or .msi installer as Intune Win32 content in CIPP storage.
    .DESCRIPTION
        Streams app-packages/<id>/installer through a zip with one entry, SHA-256, AES-256-CBC and HMAC-SHA256
        into uncommitted blocks of app-packages/<id>/IntunePackage.intunewin ([HMAC][IV][ciphertext], as
        IntuneWinAppUtil builds it), deletes the installer and writes packaged.json: the block count and package
        metadata, or the error. Saving the application template commits the blocks like a browser upload.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PackageId,
        [Parameter(Mandatory = $true)][string]$SetupFile
    )

    $Folder = "app-packages/$PackageId"
    $BlockSize = 8MB
    try {
        $Aes = [System.Security.Cryptography.Aes]::Create(); $Aes.KeySize = 256; $Aes.GenerateKey(); $Aes.GenerateIV()
        $MacKey = [byte[]]::new(32); [System.Security.Cryptography.RandomNumberGenerator]::Fill($MacKey)
        $Sha = [System.Security.Cryptography.SHA256]::Create()
        $Hmac = [System.Security.Cryptography.HMACSHA256]::new($MacKey)
        $Sink = [System.IO.MemoryStream]::new($BlockSize + 6MB)
        $HmacStream = [System.Security.Cryptography.CryptoStream]::new($Sink, $Hmac, 'Write', $true)
        $HmacStream.Write($Aes.IV, 0, 16)
        $AesStream = [System.Security.Cryptography.CryptoStream]::new($HmacStream, $Aes.CreateEncryptor(), 'Write', $true)
        $ShaStream = [System.Security.Cryptography.CryptoStream]::new($AesStream, $Sha, 'Write', $true)
        $Zip = [System.IO.Compression.ZipArchive]::new($ShaStream, 'Create', $true)
        $Entry = $Zip.CreateEntry($SetupFile, [System.IO.Compression.CompressionLevel]::Optimal).Open()

        # Block 0 is the HMAC, written once everything else is; blocks 1..N carry the IV and ciphertext.
        $Block = [byte[]]::new($BlockSize)
        $Last = [byte[]]::new(32)
        $Index = 0
        $Written = [int64]32
        $Offset = [int64]0
        $Size = [int64]-1
        $Finished = $false
        while (-not $Finished) {
            if ($Size -lt 0 -or $Offset -lt $Size) {
                $Read = New-CIPPAzStorageRequest -Service blob -Resource "$Folder/installer" -Headers @{ Range = "bytes=$Offset-$($Offset + 4MB - 1)" } -ErrorAction Stop
                # Content-Range: bytes <start>-<end>/<total>
                if ($Size -lt 0) { $Size = [int64](([string]$Read.Headers['Content-Range']) -split '/')[-1] }
                if ($Read.Length -eq 0) { throw "The installer ended at $Offset of $Size bytes" }
                $Entry.Write($Read.Bytes, 0, $Read.Length)
                $Offset += $Read.Length
            }
            if ($Offset -ge $Size) {
                $Entry.Dispose(); $Zip.Dispose()
                $ShaStream.FlushFinalBlock()   # flushes the AES and HMAC streams beneath it
                $Finished = $true
            }
            while ($Sink.Length -ge $BlockSize -or ($Finished -and $Sink.Length -gt 0)) {
                $Count = [int][Math]::Min($BlockSize, $Sink.Length)
                $Buffer = $Sink.GetBuffer()
                if (++$Index -gt 511) { throw 'The package would be larger than 4 GB' }
                $Body = $Block
                if ($Count -lt $BlockSize) { $Body = [byte[]]::new($Count) }
                [Buffer]::BlockCopy($Buffer, 0, $Body, 0, $Count)
                $null = New-CIPPAzStorageRequest -Service blob -Resource "$Folder/IntunePackage.intunewin" -Method PUT -QueryParams @{ comp = 'block'; blockid = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($Index.ToString('000'))) } -Body $Body -ContentType 'application/octet-stream' -ErrorAction Stop
                $Written += $Count
                # the last two cipher blocks give the plaintext length below
                if ($Count -ge 32) { [Buffer]::BlockCopy($Body, $Count - 32, $Last, 0, 32) } else { [Buffer]::BlockCopy($Last, $Count, $Last, 0, 32 - $Count); [Buffer]::BlockCopy($Body, 0, $Last, 32 - $Count, $Count) }
                $Rest = [int]$Sink.Length - $Count
                [Buffer]::BlockCopy($Buffer, $Count, $Buffer, 0, $Rest); $Sink.SetLength($Rest); $Sink.Position = $Rest
            }
        }
        $Mac = $Hmac.Hash
        $null = New-CIPPAzStorageRequest -Service blob -Resource "$Folder/IntunePackage.intunewin" -Method PUT -QueryParams @{ comp = 'block'; blockid = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('000')) } -Body $Mac -ContentType 'application/octet-stream' -ErrorAction Stop

        # CBC: the last cipher block decrypted and XOR-ed with the one before ends in the PKCS7 pad length.
        $Final = [byte[]]::new(16); [Buffer]::BlockCopy($Last, 16, $Final, 0, 16)
        $Pad = $Aes.DecryptEcb($Final, [System.Security.Cryptography.PaddingMode]::None)[15] -bxor $Last[15]
        $Metadata = [ordered]@{
            Name                   = $SetupFile
            SetupFile              = $SetupFile
            FileName               = 'IntunePackage.intunewin'
            UnencryptedContentSize = $Written - 48 - $Pad
            EncryptedSize          = $Written
            EncryptionInfo         = [ordered]@{
                EncryptionKey        = [Convert]::ToBase64String($Aes.Key)
                MacKey               = [Convert]::ToBase64String($MacKey)
                InitializationVector = [Convert]::ToBase64String($Aes.IV)
                Mac                  = [Convert]::ToBase64String($Mac)
                ProfileIdentifier    = 'ProfileVersion1'
                FileDigest           = [Convert]::ToBase64String($Sha.Hash)
                FileDigestAlgorithm  = 'SHA256'
            }
        }
        $Result = @{ blockCount = $Index + 1; metadata = $Metadata }
        Write-LogMessage -API 'AppPackage' -message "Packaged $SetupFile ($([Math]::Round($Size / 1MB, 1)) MB) for Intune" -Sev Info
    } catch {
        $Result = @{ error = "Could not package $($SetupFile): $($_.Exception.Message)" }
        Write-LogMessage -API 'AppPackage' -message $Result.error -Sev Error -LogData (Get-CippException -Exception $_)
    } finally {
        if ($Sink) { $Sink.Dispose() }
    }
    $null = New-CIPPAzStorageRequest -Service blob -Resource "$Folder/installer" -Method DELETE -ErrorAction SilentlyContinue
    $null = New-CIPPAzStorageRequest -Service blob -Resource "$Folder/packaged.json" -Method PUT -ContentType 'application/json' -Body ([string](ConvertTo-Json -Depth 5 -Compress -InputObject $Result)) -ErrorAction Stop
}
