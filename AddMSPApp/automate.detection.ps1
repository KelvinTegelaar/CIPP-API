$ServerAddress = '##SERVER##'
if (Get-Module -ListAvailable -Name ConnectWiseAutomateAgent) {
    Import-Module ConnectWiseAutomateAgent
}
else {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
    Install-Module -Name PowerShellGet -Force -AllowClobber
    Update-Module -Name PowerShellGet
    Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted 
    Install-Module ConnectWiseAutomateAgent -Confirm:$false
}

$AgentInfo = Get-CWAAInfo | Select-Object ID, LocationID, LastSuccessStatus, Server

if ($AgentInfo.ID -gt 0 -and $AgentInfo.LastSuccessStatus -gt (Get-Date).AddDays(-1) -and $AgentInfo.Server -contains $ServerAddress) {
    Write-Output 'SUCCESS: Agent is healthy'
    exit 0
}
else {
    Write-Output 'ERROR: Agent is not healthy'
    Write-Output $AgentInfo
    exit 1
}