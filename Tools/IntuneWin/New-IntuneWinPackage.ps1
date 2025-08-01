param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,
    [Parameter(Mandatory = $true)]
    [string]$FileName,
    [Parameter(Mandatory = $true)]
    [string]$MetadataFileName
)

# Example: .\Tools\IntuneWin\New-IntuneWinPackage.ps1 -SourcePath .\AddMSPApp\datto\ -FileName datto.intunewin -MetadataFileName datto.app.xml

$Source = Get-Item -Path $SourcePath

$Params = @(
    "-c $SourcePath"
    '-s install.ps1'
    "-o $SourcePath"
    '-q'
)

Start-Process -FilePath "$PSScriptRoot\IntuneWinAppUtil.exe" -ArgumentList $Params -Wait -NoNewWindow

Expand-Archive -Path "$SourcePath\install.intunewin" -DestinationPath $SourcePath -Force
Write-Host "IntuneWin package contents extracted to: $SourcePath"
Remove-Item -Path "$SourcePath\install.intunewin" -Force
Write-Host "Temporary IntuneWin package file removed from: $SourcePath\install.intunewin"

# Extract IntunePackage.intunewin from Contents and move to the parent directory
$IntunePackagePath = Join-Path $SourcePath 'IntuneWinPackage\Contents\IntunePackage.intunewin'
if (Test-Path -Path $IntunePackagePath) {
    Move-Item -Path $IntunePackagePath -Destination (Join-Path $Source.Parent.FullName $FileName) -Force
    Write-Host "IntunePackage.intunewin moved to: $($Source.Parent.FullName)\$FileName"
} else {
    Write-Host 'IntunePackage.intunewin not found in Contents directory.'
}

# Copy the Metadata/Detection.xml file to the parent directory
$DetectionFilePath = Join-Path $SourcePath 'IntuneWinPackage\Metadata\Detection.xml'

if (Test-Path -Path $DetectionFilePath) {
    $MetadataXml = [xml](Get-Content -Path $DetectionFilePath)
    $MetadataXml.ApplicationInfo.FileName = $FileName
    $MetadataXml.Save($DetectionFilePath)
    Write-Host "Detection.xml updated with FileName: $FileName"
} else {
    Write-Host 'Detection.xml not found in Metadata directory.'
}

if (Test-Path -Path $DetectionFilePath) {
    Copy-Item -Path $DetectionFilePath -Destination (Join-Path $Source.Parent.FullName $MetadataFileName) -Force
    Write-Host "Detection.xml copied to: $($Source.Parent.FullName)\$MetadataFileName"
} else {
    Write-Host 'Detection.xml not found in Metadata directory.'
}

# Clean up the Source directory
Remove-Item -Path $SourcePath -Recurse -Force
Write-Host "Temporary files cleaned up from: $SourcePath"
