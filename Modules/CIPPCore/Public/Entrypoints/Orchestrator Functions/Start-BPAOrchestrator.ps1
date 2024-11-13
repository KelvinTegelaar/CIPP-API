function Start-BPAOrchestrator {
    <#
    .SYNOPSIS
        Start the Best Practice Analyser
    .DESCRIPTION
        This function starts the Best Practice Analyser
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        $TenantFilter = 'AllTenants',
        [switch]$Force
    )

    try {
        if ($TenantFilter -ne 'AllTenants') {
            Write-Verbose "TenantFilter: $TenantFilter"
            if ($TenantFilter -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
                $TenantFilter = @($TenantFilter)
            } else {
                Write-Verbose 'Got GUID: Looking up tenant'
                $TenantFilter = Get-Tenants -TenantFilter $TenantFilter | Select-Object -ExpandProperty defaultDomainName
            }
            $TenantList = @($TenantFilter)
            $Name = "Best Practice Analyser ($TenantFilter)"
        } else {
            $TenantList = (Get-Tenants).defaultDomainName
            $Name = 'Best Practice Analyser'
        }

        Write-Verbose 'Getting BPA templates'
        $BPATemplateTable = Get-CippTable -tablename 'templates'
        $Filter = "PartitionKey eq 'BPATemplate'"
        $Templates = ((Get-CIPPAzDataTableEntity @BPATemplateTable -Filter $Filter).JSON | ConvertFrom-Json).Name

        Write-Verbose 'Creating orchestrator batch'
        $BPAReports = foreach ($Tenant in $TenantList) {
            foreach ($Template in $Templates) {
                [PSCustomObject]@{
                    FunctionName = 'BPACollectData'
                    Tenant       = $Tenant
                    Template     = $Template
                    QueueName    = '{0} - {1}' -f $Template, $Tenant
                }
            }
        }

        if ($Force.IsPresent) {
            Write-Host 'Clearing Rerun Cache'
            foreach ($Report in $BPAReports) {
                $null = Test-CIPPRerun -Type BPA -Tenant $Report.Tenant -API $Report.Template -Clear
            }
        }

        if (($BPAReports | Measure-Object).Count -eq 0) {
            Write-Information 'No BPA reports to run'
            return 0
        }

        if ($PSCmdlet.ShouldProcess($Name, 'Starting Orchestrator')) {
            Write-LogMessage -API 'BestPracticeAnalyser' -message 'Starting Best Practice Analyser' -sev Info
            $Queue = New-CippQueueEntry -Name $Name -TotalTasks ($BPAReports | Measure-Object).Count
            $BPAReports = $BPAReports | Select-Object *, @{Name = 'QueueId'; Expression = { $Queue.RowKey } }
            $InputObject = [PSCustomObject]@{
                Batch            = @($BPAReports)
                OrchestratorName = 'BPAOrchestrator'
                SkipLog          = $true
            }
            return Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Compress -Depth 5)
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'BestPracticeAnalyser' -message "Could not start Best Practice Analyser: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return $false
    }
}
