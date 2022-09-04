$ServerAddress = '##SERVER##'
if (Get-Module -ListAvailable -Name ConnectWiseAutomateAgent) {
    Import-Module ConnectWiseAutomateAgent
}
else {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
    Install-Module -Name PowerShellGet -Force -AllowClobber
    Update-Module -Name PowerShellGet
    Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted 
    Install-Module ConnectWiseAutomateAgent -MinimumVersion 0.1.2.0 -Confirm:$false -Force
}

Invoke-CWAACommand -Command 'Send Status'
Start-Sleep -Seconds 20

$AgentInfo = Get-CWAAInfo
$ServerPassword = ConvertFrom-CWAASecurity $AgentInfo.ServerPassword

if ($AgentInfo.ID -gt 0 -and $AgentInfo.LastSuccessStatus -gt (Get-Date).AddDays(-30) -and $AgentInfo.Server -contains $ServerAddress -and $ServerPassword -ne 'Enter the server password here.') {
    Write-Output 'SUCCESS: Agent is healthy'
    exit 0
}
else {
    Write-Output 'ERROR: Agent is not healthy'
    Write-Output $AgentInfo | Select-Object ID, LocationID, LastSuccessStatus, Server
    exit 1
}