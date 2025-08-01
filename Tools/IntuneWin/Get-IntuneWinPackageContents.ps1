param(
    $PackagePath,
    $MetadataPath
)

# Example: .\tools\IntuneWin\Get-IntuneWinPackageContents.ps1 -PackagePath .\AddMSPApp\datto.intunewin -MetadataPath .\AddMSPApp\datto.app.xml

$Metadata = [xml](Get-Content -Path $MetadataPath)
$Encryption = $Metadata.ApplicationInfo.EncryptionInfo

$Package = Get-Item $PackagePath

Write-Host "Decrypting IntuneWin package $($Package.FullName)"
Write-Host "Using encryption key: $($Encryption.EncryptionKey)"
Write-Host "Using initialization vector: $($Encryption.InitializationVector)"

$DecoderParams = @(
    "`"$($Package.FullName)`""
    "/key:`"$($Encryption.EncryptionKey)`""
    "/iv:`"$($Encryption.InitializationVector)`""
)

Start-Process -FilePath "$PSScriptRoot\IntuneWinAppUtilDecoder.exe" -ArgumentList $DecoderParams -Wait -NoNewWindow
# replace filename.intunewin with filename.decoded.zip
$NewFileName = "$($Package.BaseName -replace '\.intunewin$', '').decoded.zip"

#Extract zip
Write-Host "Extracting decrypted IntuneWin package: $($Package.DirectoryName)\$NewFileName"
Expand-Archive -Path "$($Package.DirectoryName)\$NewFileName" -DestinationPath "$($Package.DirectoryName)\$($Package.BaseName)" -Force

# Remove the decoded zip file
Remove-Item -Path "$($Package.DirectoryName)\$NewFileName" -Force
