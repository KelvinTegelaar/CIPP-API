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
    $Types = $Request.Query.Types

    Write-Information "ExecCIPPDBCache called with Name: '$Name', TenantFilter: '$TenantFilter', Types: '$Types'"

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
                $BatchItem = [PSCustomObject]@{
                    FunctionName = 'ExecCIPPDBCache'
                    Name         = $Name
                    QueueName    = "$Name Cache - $($_.defaultDomainName)"
                    TenantFilter = $_.defaultDomainName
                    QueueId      = $Queue.RowKey
                }
                # Add Types parameter if provided
                if ($Types) {
                    $BatchItem | Add-Member -NotePropertyName 'Types' -NotePropertyValue @($Types -split ',') -Force
                }
                $BatchItem
            }

            $InputObject = [PSCustomObject]@{
                Batch            = @($Batch)
                OrchestratorName = "CIPPDBCache_${Name}_AllTenants"
                SkipLog          = $false
            }

            Write-LogMessage -Headers $Request.Headers -API $APIName -tenant $TenantFilter -message "Starting CIPP DB cache for $Name across $($TenantList.Count) tenants" -sev Info
        } else {
            # Single tenant
            $Queue = New-CippQueueEntry -Name $QueueName -TotalTasks 1

            $BatchItem = [PSCustomObject]@{
                FunctionName = 'ExecCIPPDBCache'
                Name         = $Name
                QueueName    = "$Name Cache - $TenantFilter"
                TenantFilter = $TenantFilter
                QueueId      = $Queue.RowKey
            }
            # Add Types parameter if provided
            if ($Types) {
                $BatchItem | Add-Member -NotePropertyName 'Types' -NotePropertyValue @($Types -split ',') -Force
            }

            $InputObject = [PSCustomObject]@{
                Batch            = @($BatchItem)
                OrchestratorName = "CIPPDBCache_${Name}_$TenantFilter"
                SkipLog          = $false
            }
            Write-LogMessage -Headers $Request.Headers -API $APIName -tenant $TenantFilter -message "Starting CIPP DB cache for $Name on tenant $TenantFilter" -sev Info
        }

        $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Compress -Depth 5)

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
