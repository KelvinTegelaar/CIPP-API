function Invoke-ExecManagedBaselineRecommendation {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Baselines.ReadWrite
    .DESCRIPTION
        Manages the Managed Baselines recommendations of one tenant (tenantFilter). Action is Scan or Generate. Scan downloads CyberDrain's recommendation list and compares the tenant against every standard on it in the background; nothing about the tenant is sent and nothing is imported. Generate takes the chosen rows (rows, or every recommended row when empty) and prepares the baseline the editor opens; it saves no baseline.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Action = "$($Request.Body.Action)"
    try {
        if (-not (Test-CIPPManagedBaselinesEnabled)) {
            throw [System.ArgumentException]::new('The CyberDrain Managed Baselines integration is not enabled. Enable it under Integrations.')
        }
        $TenantFilter = "$($Request.Body.tenantFilter.value ?? $Request.Body.tenantFilter)"
        $Tenant = $null
        if ($TenantFilter -and $TenantFilter -notin @('AllTenants', 'allTenants')) {
            $Tenant = Get-Tenants -TenantFilter $TenantFilter | Select-Object -First 1
        }
        if (-not $Tenant.defaultDomainName) { throw [System.ArgumentException]::new('Choose one tenant.') }
        $Partition = "$($Tenant.customerId)"
        $Table = Get-CippTable -tablename 'BaselineRecommendations'
        $Metadata = @{ tenantFilter = "$($Tenant.defaultDomainName)" }

        if ($Action -eq 'Scan') {
            $User = $(try { ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails } catch { $null })
            $Started = Start-CIPPManagedBaselineRecommendationScan -Tenant $Tenant -StartedBy "$User"
            $Message = "Scan started. CIPP is comparing $($Tenant.defaultDomainName) against $($Started.Total) recommendations."
            $Metadata.total = $Started.Total
        } elseif ($Action -eq 'Generate') {
            $Rows = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$(ConvertTo-CIPPODataFilterValue -Value $Partition)'")
            $Scan = $Rows.Where({ $_.RowKey -eq 'scan' }, 'First')[0]
            if (-not $Scan) { throw [System.ArgumentException]::new("Scan $($Tenant.defaultDomainName) first.") }

            $Asked = @($Request.Body.rows | ForEach-Object { "$($_.rowKey ?? $_)" } | Where-Object { $_ })
            $Chosen = if ($Asked.Count -gt 0) {
                @($Rows.Where({ $_.RowKey -in $Asked -and "$($_.Status)" -in @('Recommended', 'Covered by a baseline') }))
            } else {
                @($Rows.Where({ "$($_.Status)" -eq 'Recommended' }))
            }
            if ($Chosen.Count -eq 0) { throw [System.ArgumentException]::new('There is no recommendation to build a baseline from.') }

            Add-CIPPAzDataTableEntity @Table -Entity @{
                PartitionKey = $Partition
                RowKey       = 'scan'
                Selection    = [string](ConvertTo-Json -Compress -InputObject @($Chosen.RowKey))
                SelectedAt   = [int64]([datetimeoffset]::UtcNow.ToUnixTimeSeconds())
            } -OperationType UpsertMerge

            $Message = "Prepared a baseline with $($Chosen.Count) standards. Nothing is saved until you save it in the editor."
        } else {
            throw [System.ArgumentException]::new("Unknown action '$Action'. Use Scan or Generate.")
        }
        Write-LogMessage -headers $Request.Headers -API $APIName -tenant $Tenant.defaultDomainName -message "Managed baseline recommendations for $($Tenant.defaultDomainName): $Action. $Message" -Sev 'Info'
        $Results = [PSCustomObject]@{ Results = $Message; Metadata = $Metadata }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APIName -message "Managed baseline recommendations $Action failed: $($_.Exception.Message)" -Sev 'Error'
        $Results = [PSCustomObject]@{ Results = "$($_.Exception.Message)" }
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
