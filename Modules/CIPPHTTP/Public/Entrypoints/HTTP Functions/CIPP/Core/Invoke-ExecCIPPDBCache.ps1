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

    $ParsedTypes = @()
    if (-not [string]::IsNullOrWhiteSpace($Types)) {
        $ParsedTypes = @($Types -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and $_ -ne 'None' })
    }

    Write-Information "ExecCIPPDBCache called with Name: '$Name', TenantFilter: '$TenantFilter', Types: '$Types'"

    try {
        if ([string]::IsNullOrEmpty($Name)) {
            throw 'Name parameter is required'
        }

        if ([string]::IsNullOrEmpty($TenantFilter)) {
            throw 'TenantFilter parameter is required'
        }

        # A derived cache type has no collector of its own — it is produced as a side-effect of
        # another collector (e.g. SharePointSiteListing by Set-CIPPDBCacheSharePointSiteUsage). The
        # registry's 'collectedBy' names that producing collector, so a run of the derived type runs
        # it and populates the derived data.
        $CacheTypesPath = Join-Path $env:CIPPRootPath 'Config/CIPPDBCacheTypes.json'
        if (Test-Path $CacheTypesPath) {
            $CollectedBy = ((Get-Content $CacheTypesPath -Raw | ConvertFrom-Json) | Where-Object { $_.type -eq $Name }).collectedBy
            if ($CollectedBy) {
                Write-Information "ExecCIPPDBCache: '$Name' is a derived cache type; running its producing collector '$CollectedBy'"
                $Name = "$CollectedBy"
            }
        }

        $FunctionName = "Set-CIPPDBCache$Name"
        if (-not (Resolve-CIPPCommand -Name $FunctionName)) {
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
                if ($ParsedTypes.Count -gt 0) {
                    $BatchItem | Add-Member -NotePropertyName 'Types' -NotePropertyValue $ParsedTypes -Force
                }
                $BatchItem
            }

            $InputObject = [PSCustomObject]@{
                Batch            = @($Batch)
                OrchestratorName = "CIPPDBCache_${Name}_AllTenants"
                AllowCollision   = $false
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
            if ($ParsedTypes.Count -gt 0) {
                $BatchItem | Add-Member -NotePropertyName 'Types' -NotePropertyValue $ParsedTypes -Force
            }

            $InputObject = [PSCustomObject]@{
                Batch            = @($BatchItem)
                OrchestratorName = "CIPPDBCache_${Name}_$TenantFilter"
                AllowCollision   = $false
                SkipLog          = $false
            }
            Write-LogMessage -Headers $Request.Headers -API $APIName -tenant $TenantFilter -message "Starting CIPP DB cache for $Name on tenant $TenantFilter" -sev Info
        }

        $InstanceId = Start-CIPPOrchestrator -InputObject $InputObject

        $Skipped = "$InstanceId" -like '*-Skipped'
        $Scope = if ($TenantFilter -eq 'AllTenants') { 'for all tenants' } else { "on tenant $TenantFilter" }
        $ResultsMessage = if ($Skipped) {
            "A $Name cache operation is already running $Scope, so this request was skipped"
        } else {
            "Successfully started cache operation for $Name $Scope"
        }

        $Body = [PSCustomObject]@{
            Results  = $ResultsMessage
            Metadata = @{
                Name       = $Name
                Tenant     = $TenantFilter
                InstanceId = $InstanceId
                QueueId    = if ($Skipped) { $null } else { $Queue.RowKey }
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
