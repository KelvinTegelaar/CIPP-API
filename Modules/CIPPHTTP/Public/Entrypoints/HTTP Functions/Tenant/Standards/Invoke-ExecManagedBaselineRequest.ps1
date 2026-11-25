function Invoke-ExecManagedBaselineRequest {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Baselines.ReadWrite
    .DESCRIPTION
        Requests a custom baseline from CyberDrain through the Managed Baselines integration and manages that request. Action is Create (tenantFilter, industry, clientSize and wants, optionally exceptions, frameworks and comments), or Refresh, Retry or Cancel (requestId). Create compares the tenant against every available standard in the background and sends the results with what was typed. Text that names the tenant, or holds an email address, an IP address or an ID, is refused.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Action = "$($Request.Body.Action)"
    try {
        $User = $(try { ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails } catch { $null })
        $Table = Get-CippTable -tablename 'ManagedBaselineRequests'
        $CollectionTable = Get-CippTable -tablename 'ManagedBaselineCollection'
        $Now = [int64]([datetimeoffset]::UtcNow.ToUnixTimeSeconds())

        # Everything that names the tenant: checked against what is typed, and removed from the snapshot.
        $IdentifiersOf = {
            param($Tenant)
            $Identifiers = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($Value in @($Tenant.displayName, $Tenant.defaultDomainName, $Tenant.initialDomainName, $Tenant.customerId)) {
                if ("$Value".Trim()) { $null = $Identifiers.Add("$Value".Trim()) }
            }
            foreach ($Domain in @($Tenant.defaultDomainName, $Tenant.initialDomainName)) {
                if ("$Domain" -match '^([^.]+)\.onmicrosoft\.com$') { $null = $Identifiers.Add($Matches[1]) }
            }
            try {
                foreach ($Domain in @(New-CIPPDbRequest -TenantFilter $Tenant.defaultDomainName -Type 'Domains')) {
                    if ("$($Domain.id)".Trim()) { $null = $Identifiers.Add("$($Domain.id)".Trim()) }
                }
            } catch {
                Write-Information "Managed baseline request: the cached domains of $($Tenant.defaultDomainName) could not be read: $($_.Exception.Message)"
            }
            , [string[]]@($Identifiers)
        }
        # One compare per standard, then the snapshot is sent once they have all finished.
        $StartCollection = {
            param($RequestId, $Tenant, $Identifiers)
            $Covered = @{}
            try {
                foreach ($WorkItem in @(Get-CIPPBaselineWorkItems -TenantFilter $Tenant.defaultDomainName)) {
                    if ($WorkItem.BaseName) { $Covered["$($WorkItem.BaseName)"] = $true }
                }
            } catch {
                Write-Information "Managed baseline request: the baselines covering $($Tenant.defaultDomainName) could not be resolved: $($_.Exception.Message)"
            }
            # A definition leaves itself out of every snapshot with "managedCollection": false.
            $Definitions = @(Get-CIPPBaselineDefinition | Where-Object { $_.name -and $_.disabled -ne $true -and $_.managedCollection -ne $false -and -not $_.package -and -not $_.manual })
            $Queue = New-CippQueueEntry -Name "Managed baseline snapshot ($($Definitions.Count) standards) - $($Tenant.defaultDomainName)" -Reference 'ManagedBaselineSnapshot' -TotalTasks $Definitions.Count
            $Batch = foreach ($Definition in $Definitions) {
                [PSCustomObject]@{
                    FunctionName      = 'CIPPManagedBaselineCollect'
                    RequestId         = $RequestId
                    TenantFilter      = "$($Tenant.defaultDomainName)"
                    Standard          = "$($Definition.name)"
                    InBaseline        = $Covered.ContainsKey("$($Definition.name)")
                    TenantIdentifiers = $Identifiers
                    QueueId           = $Queue.RowKey
                    QueueName         = ('{0} - {1}' -f $Definition.name, $Tenant.defaultDomainName)
                }
            }
            $null = Start-CIPPOrchestrator -InputObject ([PSCustomObject]@{
                    Batch            = @($Batch)
                    OrchestratorName = "ManagedBaselineSnapshot_$RequestId"
                    SkipLog          = $true
                    PostExecution    = @{
                        FunctionName = 'CIPPManagedBaselineSubmit'
                        Parameters   = @{ RequestId = $RequestId }
                    }
                })
            $Definitions.Count
        }
        $ClearCollection = {
            param($RequestId)
            $SafeId = ConvertTo-CIPPODataFilterValue -Value $RequestId
            $Collected = @(Get-CIPPAzDataTableEntity @CollectionTable -Filter "PartitionKey eq '$SafeId'" -Property PartitionKey, RowKey)
            if ($Collected.Count -gt 0) { Remove-CIPPAzDataTableEntity -Force @CollectionTable -Entity $Collected }
        }

        if ($Action -eq 'Create') {
            $TenantFilter = "$($Request.Body.tenantFilter.value ?? $Request.Body.tenantFilter)"
            $Tenant = $null
            if ($TenantFilter -and $TenantFilter -notin @('AllTenants', 'allTenants')) {
                $Tenant = Get-Tenants -TenantFilter $TenantFilter | Select-Object -First 1
            }
            if (-not $Tenant.defaultDomainName) { throw [System.ArgumentException]::new('Choose the tenant to snapshot.') }

            $Typed = [ordered]@{
                Industry   = "$($Request.Body.industry.value ?? $Request.Body.industry)".Trim()
                ClientSize = "$($Request.Body.clientSize.value ?? $Request.Body.clientSize)".Trim()
                Wants      = "$($Request.Body.wants)".Trim()
                Exceptions = "$($Request.Body.exceptions)".Trim()
                Comments   = "$($Request.Body.comments)".Trim()
            }
            $Frameworks = @($Request.Body.frameworks | ForEach-Object { "$($_.value ?? $_)".Trim() } | Where-Object { $_ })
            $Labels = [ordered]@{ Industry = 'Industry'; ClientSize = 'Client size'; Wants = 'What you expect'; Exceptions = 'Exceptions'; Comments = 'Comments' }
            foreach ($Field in @('Industry', 'ClientSize', 'Wants')) {
                if (-not $Typed[$Field]) { throw [System.ArgumentException]::new("$($Labels[$Field]) is required.") }
            }

            $Identifiers = & $IdentifiersOf $Tenant
            $Refusal = 'Describe it instead of naming it, so nothing that identifies the tenant is sent to CyberDrain.'
            foreach ($Field in $Typed.Keys) {
                $Found = Test-CIPPManagedBaselineIdentifier -Text $Typed[$Field] -TenantIdentifiers $Identifiers
                if ($Found) { throw [System.ArgumentException]::new("$($Labels[$Field]) contains $Found. $Refusal") }
            }
            foreach ($Framework in $Frameworks) {
                $Found = Test-CIPPManagedBaselineIdentifier -Text $Framework -TenantIdentifiers $Identifiers
                if ($Found) { throw [System.ArgumentException]::new("Frameworks contains $Found. $Refusal") }
            }

            $RequestId = [string](New-Guid).Guid
            Add-CIPPAzDataTableEntity @Table -Entity @{
                PartitionKey = 'request'
                RowKey       = $RequestId
                TenantFilter = "$($Tenant.defaultDomainName)"
                Industry     = $Typed.Industry
                ClientSize   = $Typed.ClientSize
                Wants        = $Typed.Wants
                Exceptions   = $Typed.Exceptions
                Frameworks   = [string](ConvertTo-Json -Compress -InputObject @($Frameworks))
                Comments     = $Typed.Comments
                Status              = 'Waiting on data collection'
                CreatedBy           = "$User"
                CreatedAt           = $Now
                CollectionStartedAt = $Now
            } -Force
            try {
                $Total = & $StartCollection $RequestId $Tenant $Identifiers
            } catch {
                Add-CIPPAzDataTableEntity @Table -Entity @{ PartitionKey = 'request'; RowKey = $RequestId; Status = 'Failed'; Error = "Data collection could not be started: $($_.Exception.Message)" } -OperationType UpsertMerge
                throw
            }
            Add-CIPPAzDataTableEntity @Table -Entity @{ PartitionKey = 'request'; RowKey = $RequestId; Total = $Total } -OperationType UpsertMerge

            $Message = "Request created. CIPP is comparing $($Tenant.defaultDomainName) against $Total standards and sends the result to CyberDrain when that finishes."
            Write-LogMessage -headers $Request.Headers -API $APIName -tenant $Tenant.defaultDomainName -message "Requested a custom managed baseline for $($Tenant.defaultDomainName) ($RequestId)." -Sev 'Info'
            $Results = [PSCustomObject]@{ Results = $Message; Metadata = @{ requestId = $RequestId } }
        } elseif ($Action -in @('Refresh', 'Retry', 'Cancel')) {
            $RequestId = "$($Request.Body.requestId)"
            $SafeId = ConvertTo-CIPPODataFilterValue -Value $RequestId
            $Row = $null
            if ($RequestId) {
                $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'request' and RowKey eq '$SafeId'" |
                    Select-CippAllowedTenantData -TenantProperty 'TenantFilter' | Select-Object -First 1
            }
            if (-not $Row) { throw [System.Management.Automation.ItemNotFoundException]::new('That request was not found.') }

            if ($Action -eq 'Refresh') {
                if (-not $Row.SubmittedAt) {
                    $Message = "This request has not been sent to CyberDrain yet. Its status is '$($Row.Status)'."
                } else {
                    $Status = Update-CIPPManagedBaselineRequest -Row $Row
                    $Message = "CyberDrain was asked. The status is '$Status'."
                }
            } elseif ($Action -eq 'Retry') {
                if ("$($Row.Status)" -ne 'Failed') { throw [System.ArgumentException]::new("Only a failed request can be retried. This one is '$($Row.Status)'.") }
                $Tenant = Get-Tenants -TenantFilter $Row.TenantFilter | Select-Object -First 1
                if (-not $Tenant.defaultDomainName) { throw [System.ArgumentException]::new("$($Row.TenantFilter) is no longer a tenant in this CIPP.") }
                & $ClearCollection $RequestId
                Add-CIPPAzDataTableEntity @Table -Entity @{ PartitionKey = 'request'; RowKey = $RequestId; Status = 'Waiting on data collection'; Error = ''; CollectionStartedAt = $Now } -OperationType UpsertMerge
                $Total = & $StartCollection $RequestId $Tenant (& $IdentifiersOf $Tenant)
                Add-CIPPAzDataTableEntity @Table -Entity @{ PartitionKey = 'request'; RowKey = $RequestId; Total = $Total } -OperationType UpsertMerge
                $Message = "Started again. CIPP is comparing $($Tenant.defaultDomainName) against $Total standards."
            } else {
                if ("$($Row.Status)" -eq 'Implemented') { throw [System.ArgumentException]::new('This request is implemented and can no longer be cancelled.') }
                if ($Row.SubmittedAt) {
                    try {
                        $null = Invoke-ManagedBaselinesRequest -Path "requests/$RequestId" -Method DELETE
                    } catch {
                        Write-LogMessage -headers $Request.Headers -API $APIName -tenant $Row.TenantFilter -message "Cancelling request $RequestId at CyberDrain failed, it was removed here only: $($_.Exception.Message)" -Sev 'Warning'
                    }
                }
                & $ClearCollection $RequestId
                Remove-CIPPAzDataTableEntity -Force @Table -Entity ($Row | Select-Object -Property PartitionKey, RowKey)
                $Message = "Cancelled the request for $($Row.TenantFilter)."
            }
            Write-LogMessage -headers $Request.Headers -API $APIName -tenant $Row.TenantFilter -message "Managed baseline request $RequestId for $($Row.TenantFilter): $Action. $Message" -Sev 'Info'
            $Results = [PSCustomObject]@{ Results = $Message; Metadata = @{ requestId = $RequestId } }
        } else {
            throw [System.ArgumentException]::new("Unknown action '$Action'. Use Create, Refresh, Retry or Cancel.")
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APIName -message "Managed baseline request $Action failed: $($_.Exception.Message)" -Sev 'Error'
        $Results = [PSCustomObject]@{ Results = "$($_.Exception.Message)" }
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
