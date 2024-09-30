function Invoke-ExecBPA {
    <#
        .FUNCTIONALITY
        Entrypoint
        .ROLE
        Tenant.BestPracticeAnalyser.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $ConfigTable = Get-CIPPTable -tablename Config
    $Config = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'OffloadFunctions' and RowKey eq 'OffloadFunctions'"

    if ($Config -and $Config.state -eq $true) {
        if ($env:CIPP_PROCESSOR -ne 'true') {
            $ProcessorQueue = Get-CIPPTable -TableName 'ProcessorQueue'
            $ProcessorFunction = [PSCustomObject]@{
                PartitionKey = 'Function'
                RowKey       = "Start-BPAOrchestrator-$($Request.Query.TenantFilter)"
                FunctionName = 'Start-BPAOrchestrator'
                Parameters   = [string](ConvertTo-Json -Compress -InputObject @{
                        TenantFilter = $Request.Query.TenantFilter
                    })
            }
            Add-AzDataTableEntity @ProcessorQueue -Entity $ProcessorFunction -Force
            $Results = [pscustomobject]@{'Results' = 'BPA queued for execution' }
        }
    } else {
        Start-BPAOrchestrator -TenantFilter $Request.Query.TenantFilter
        $Results = [pscustomobject]@{'Results' = 'BPA started' }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
