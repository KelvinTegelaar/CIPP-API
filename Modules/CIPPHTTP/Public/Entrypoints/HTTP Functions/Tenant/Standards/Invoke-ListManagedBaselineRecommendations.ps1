function Invoke-ListManagedBaselineRecommendations {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Baselines.Read
    .DESCRIPTION
        Lists the Managed Baselines recommendations that apply to one tenant (tenantFilter) from its last scan, which are the entries of CyberDrain's list the tenant differs on, with the state of that scan in Metadata. With draft it returns the baseline that Generate prepared, in the shape the baseline editor loads: one stage with the chosen standards, all with remediation off.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    try {
        if (-not (Test-CIPPManagedBaselinesEnabled)) {
            throw [System.ArgumentException]::new('The CyberDrain Managed Baselines integration is not enabled. Enable it under Integrations.')
        }
        $TenantFilter = "$($Request.Query.tenantFilter)"
        $Tenant = $null
        if ($TenantFilter -and $TenantFilter -notin @('AllTenants', 'allTenants')) {
            $Tenant = Get-Tenants -TenantFilter $TenantFilter | Select-Object -First 1
        }
        if (-not $Tenant.defaultDomainName) { throw [System.ArgumentException]::new('Choose one tenant.') }
        $Partition = "$($Tenant.customerId)"
        $Table = Get-CippTable -tablename 'BaselineRecommendations'
        $Rows = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$(ConvertTo-CIPPODataFilterValue -Value $Partition)'")
        $Scan = $Rows.Where({ $_.RowKey -eq 'scan' }, 'First')[0]
        $Findings = @($Rows.Where({ $_.RowKey -ne 'scan' }))
        $FromJson = {
            param($Text)
            if (-not "$Text") { return $null }
            try { ConvertFrom-Json -InputObject "$Text" -Depth 100 -ErrorAction Stop } catch { $null }
        }
        # A stored list that is empty or missing must come back as an empty array, not as one null.
        $ListFromJson = {
            param($Text)
            , @(@(& $FromJson $Text).Where({ $null -ne $_ }))
        }

        if ("$($Request.Query.draft)" -eq 'true') {
            $Selection = & $ListFromJson $Scan.Selection
            $Chosen = @($Findings.Where({ $_.RowKey -in $Selection }))
            if ($Chosen.Count -eq 0) { throw [System.ArgumentException]::new('No baseline has been prepared for this tenant. Use Generate Baseline on the recommendations first.') }

            $Configs = foreach ($Row in ($Chosen | Sort-Object -Property RowKey)) {
                [PSCustomObject]@{
                    standard         = "$($Row.Standard)"
                    instance         = "$($Row.Standard)"
                    variables        = (& $FromJson $Row.Variables) ?? [PSCustomObject]@{}
                    remediateEnabled = $false
                    alertEnabled     = $true
                    alertOnRemediate = $false
                }
            }
            $Stages = @([PSCustomObject]@{
                    name            = 'Baseline'
                    logic           = 'and'
                    conditions      = @()
                    conditionGroups = @()
                    standards       = @($Configs.instance)
                    standardsConfig = @($Configs)
                })
            $TenantLabel = "$($Tenant.defaultDomainName)"
            if ($Tenant.displayName) { $TenantLabel = '{0} ({1})' -f $Tenant.displayName, $Tenant.defaultDomainName }
            $TenantOption = [PSCustomObject]@{ value = "$($Tenant.defaultDomainName)"; label = $TenantLabel; type = 'Tenant' }
            $Body = @{
                Results = [PSCustomObject]@{
                    GUID                 = "recommendation-$Partition-$($Scan.SelectedAt)"
                    templateName         = "Recommendations - $($Tenant.displayName ?? $Tenant.defaultDomainName)"
                    description          = 'Built from the Managed Baselines recommendations for this tenant.'
                    assignments          = @($TenantOption)
                    assignedTenants      = @("$($Tenant.defaultDomainName)")
                    exclusions           = @()
                    excludedTenants      = @()
                    alertEmails          = ''
                    alertWebhookUrl      = ''
                    disableAlerts        = $false
                    disableScheduledRuns = $false
                    stages               = @($Stages)
                }
            }
        } else {
            $Definitions = @{}
            foreach ($Definition in @(Get-CIPPBaselineDefinition)) { if ($Definition.name) { $Definitions["$($Definition.name)"] = $Definition } }
            # Only what the tenant differs on is a recommendation for it.
            $Results = foreach ($Row in $Findings.Where({ "$($_.Status)" -in @('Recommended', 'Covered by a baseline') })) {
                $Definition = $Definitions["$($Row.Standard)"]
                $Differences = & $ListFromJson $Row.Differences
                [PSCustomObject]@{
                    rowKey            = $Row.RowKey
                    recommendation    = "$($Row.Title)" ? "$($Row.Title)" : "$($Definition.label ?? $Row.Standard)"
                    standard          = $Row.Standard
                    category          = "$($Definition.cat)"
                    impact            = "$($Row.Impact)" ? "$($Row.Impact)" : "$($Definition.impact)"
                    frameworks        = @(@($Definition.tag).Where({ $_ }))
                    status            = $Row.Status
                    differsOn         = @(@($Differences.Property).Where({ $_ }))
                    firstSeenDateTime = [int64]($Row.FirstSeen ?? 0) -gt 0 ? [int64]$Row.FirstSeen : $null
                    reason            = $Row.Reason
                    helpText          = $Definition.helpText
                    currentValue      = & $FromJson $Row.Current
                    differences       = $Differences
                }
            }
            $Compared = 0
            if ($Scan) { $Compared = @($Findings.Where({ "$($_.ScanId)" -eq "$($Scan.ScanId)" })).Count }
            $Body = @{
                Results  = @($Results)
                Metadata = @{
                    scan = $Scan ? [PSCustomObject]@{
                        status                 = $Scan.Status
                        startedDateTime        = $Scan.StartedAt
                        finishedDateTime       = $Scan.FinishedAt
                        startedBy              = $Scan.StartedBy
                        listVersion            = $Scan.ListVersion
                        total                  = $Scan.Total
                        compared               = $Compared
                        skipped                = $Scan.Skipped
                        newFindings            = $Scan.NewFindings
                        resolvedFindings       = $Scan.ResolvedFindings
                        error                  = $Scan.Error
                    } : $null
                }
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APIName -message "Failed to list managed baseline recommendations: $($_.Exception.Message)" -Sev 'Error'
        $Body = @{ Results = "Failed to list managed baseline recommendations: $($_.Exception.Message)" }
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
