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
            $Parameters = @{Force = $true }
            if ($Request.Query.TenantFilter) {
                $Parameters.TenantFilter = $Request.Query.TenantFilter
                $RowKey = "Start-BPAOrchestrator-$($Request.Query.TenantFilter)"
            } else {
                $RowKey = 'Start-BPAOrchestrator'
            }

            $ProcessorQueue = Get-CIPPTable -TableName 'ProcessorQueue'
            $ProcessorFunction = [PSCustomObject]@{
                PartitionKey = 'Function'
                RowKey       = $RowKey
                FunctionName = 'Start-BPAOrchestrator'
                Parameters   = [string](ConvertTo-Json -Compress -InputObject $Parameters)
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
