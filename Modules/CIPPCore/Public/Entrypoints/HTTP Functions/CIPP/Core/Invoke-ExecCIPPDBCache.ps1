function Invoke-ExecCIPPDBCache {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.TenantFilter
    $Name = $Request.Query.Name

    Write-Information "ExecCIPPDBCache called with Name: '$Name', TenantFilter: '$TenantFilter'"

    try {
        if ([string]::IsNullOrEmpty($Name)) {
            throw 'Name parameter is required'
        }

        if ([string]::IsNullOrEmpty($TenantFilter)) {
            throw 'TenantFilter parameter is required'
        }

        # Validate the function exists
        $FunctionName = "Set-CIPPDBCache$Name"
        $Function = Get-Command -Name $FunctionName -ErrorAction SilentlyContinue
        if (-not $Function) {
            throw "Cache function '$FunctionName' not found"
        }

        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Starting CIPP DB cache for $Name" -sev Info

        # Create queue entry for tracking
        $QueueName = if ($TenantFilter -eq 'AllTenants') {
            "$Name Cache Sync (All Tenants)"
        } else {
            "$Name Cache Sync ($TenantFilter)"
        }

        # Handle AllTenants - create a batch for each tenant
        if ($TenantFilter -eq 'AllTenants') {
            $TenantList = Get-Tenants -IncludeErrors
            $Queue = New-CippQueueEntry -Name $QueueName -TotalTasks ($TenantList | Measure-Object).Count

            $Batch = $TenantList | ForEach-Object {
                [PSCustomObject]@{
                    FunctionName = 'ExecCIPPDBCache'
                    QueueName    = "$Name Cache - $($_.defaultDomainName)"
                    Name         = $Name
                    TenantFilter = $_.defaultDomainName
                    QueueId      = $Queue.RowKey
                }
            }

            $InputObject = [PSCustomObject]@{
                Batch            = @($Batch)
                OrchestratorName = "CIPPDBCache_${Name}_AllTenants"
                SkipLog          = $false
            }

            Write-LogMessage -API $APIName -tenant $TenantFilter -message "Starting CIPP DB cache for $Name across $($TenantList.Count) tenants" -sev Info
        } else {
            # Single tenant
            $Queue = New-CippQueueEntry -Name $QueueName -TotalTasks 1

            $InputObject = [PSCustomObject]@{
                Batch            = @([PSCustomObject]@{
                        QueueName    = "$Name Cache - $TenantFilter"
                        FunctionName = 'ExecCIPPDBCache'
                        Name         = $Name
                        TenantFilter = $TenantFilter
                        QueueId      = $Queue.RowKey
                    })
                OrchestratorName = "CIPPDBCache_${Name}_$TenantFilter"
                SkipLog          = $false
            }
        }

        $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Compress -Depth 5)

        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Started CIPP DB cache orchestrator for $Name with instance ID: $InstanceId" -sev Info

        $ResultsMessage = if ($TenantFilter -eq 'AllTenants') {
            "Successfully started cache operation for $Name for all tenants"
        } else {
            "Successfully started cache operation for $Name on tenant $TenantFilter"
        }

        $Body = [PSCustomObject]@{
            Results  = $ResultsMessage
            Metadata = @{
                Name       = $Name
                Tenant     = $TenantFilter
                InstanceId = $InstanceId
                QueueId    = $Queue.RowKey
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Failed to start CIPP DB cache for $Name : $ErrorMessage" -sev Error
        $Body = [PSCustomObject]@{
            Results = "Failed to start cache operation: $ErrorMessage"
        }
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
