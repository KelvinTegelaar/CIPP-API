function Invoke-ExecBPA {
    <#
        .FUNCTIONALITY
        Entrypoint,AnyTenant
        .ROLE
        Tenant.BestPracticeAnalyser.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $ConfigTable = Get-CIPPTable -tablename Config
    $Config = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'OffloadFunctions' and RowKey eq 'OffloadFunctions'"

    $TenantFilter = $Request.Query.tenantFilter ? $Request.Query.tenantFilter.value : $Request.Body.tenantFilter.value

    if ($Config -and $Config.state -eq $true) {
        if ($env:CIPP_PROCESSOR -ne 'true') {
            $Parameters = @{Force = $true }
            if ($TenantFilter -and $TenantFilter -ne 'AllTenants') {
                $Parameters.TenantFilter = $TenantFilter
                $RowKey = "Start-BPAOrchestrator-$($TenantFilter)"
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
            $Results = 'BPA queued for execution'
        }
    } else {
        Start-BPAOrchestrator -TenantFilter $TenantFilter
        $Results = 'BPA started'
    }

    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{ Results = $Results }
    }
}
