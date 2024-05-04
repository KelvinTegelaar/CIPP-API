param($Timer)

if ($env:DEV_SKIP_BPA_TIMER) {
    Write-Host 'Skipping BPA timer'
    exit 0
}

$TenantList = Get-Tenants

$CippRoot = (Get-Item $PSScriptRoot).Parent.FullName
$TemplatesLoc = Get-ChildItem "$CippRoot\Config\*.BPATemplate.json"
$Templates = $TemplatesLoc | ForEach-Object {
    $Template = $(Get-Content $_) | ConvertFrom-Json
    $Template.Name
}

$BPAReports = foreach ($Tenant in $TenantList) {
    foreach ($Template in $Templates) {
        [PSCustomObject]@{
            FunctionName = 'BPACollectData'
            Tenant       = $Tenant.defaultDomainName
            Template     = $Template
            QueueName    = '{0} - {1}' -f $Template, $Tenant.defaultDomainName
        }
    }
}

$Queue = New-CippQueueEntry -Name 'Best Practice Analyser' -TotalTasks ($BPAReports | Measure-Object).Count
$BPAReports = $BPAReports | Select-Object *, @{Name = 'QueueId'; Expression = { $Queue.RowKey } }
$InputObject = [PSCustomObject]@{
    Batch            = @($BPAReports)
    OrchestratorName = 'BPAOrchestrator'
    SkipLog          = $true
    DurableMode      = 'Sequence'
}
Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Compress -Depth 5)
