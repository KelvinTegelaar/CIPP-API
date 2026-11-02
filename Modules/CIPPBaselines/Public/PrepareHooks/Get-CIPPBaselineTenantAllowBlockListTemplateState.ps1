function Get-CIPPBaselineTenantAllowBlockListTemplateState {
    <#
    .SYNOPSIS
        Prepare hook for TenantAllowBlockListTemplate: which of this instance's entries are
        missing.
    .DESCRIPTION
        One instance grades ONE template, but a template here is a SET of entries for one
        list type, not a single object - the graded shape is the missing-entries list, the
        same additive compare the classic ran. Entries an operator added by hand are never
        graded or touched; this family only ever ADDS.

        Entries split on commas and semicolons and trim, exactly as the classic parsed them.
        Presence is checked against the cached Tenant Allow/Block List rows for the
        template's listType; matching is case-insensitive, which is what the classic's
        -notcontains did.

        Expired entries drop out of the tenant list, so a previously-deployed entry whose
        expiration passed reads as missing again and remediation re-adds it - for a
        block-list template that re-detection is the point.

        Template resolution stays per-family: PartitionKey 'TenantAllowBlockListTemplate',
        RowKey alone.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $ListItems = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoTenantAllowBlockList')
    if ($ListItems.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'ExoTenantAllowBlockList')) {
        return @{ Current = $null }
    }

    $Reference = $Item.Variables.tenantAllowBlockListTemplate
    if ($Reference -is [System.Management.Automation.PSCustomObject] -and $Reference.PSObject.Properties.Name -contains 'value') { $Reference = $Reference.value }
    if ([string]::IsNullOrWhiteSpace("$Reference")) { return @{ Current = $null } }

    $Table = Get-CippTable -tablename 'templates'
    $SafeReference = ConvertTo-CIPPODataFilterValue -Value "$Reference"
    $Entity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'TenantAllowBlockListTemplate' and RowKey eq '$SafeReference'" | Select-Object -First 1
    $Template = $(if ($Entity -and -not [string]::IsNullOrWhiteSpace($Entity.JSON)) { try { $Entity.JSON | ConvertFrom-Json -Depth 10 -ErrorAction Stop } catch { $null } })
    if (-not $Template) { return @{ Current = $null } }

    $Entries = @("$($Template.entries)" -split '[,;]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
    $ListType = "$($Template.listType)"
    if ($Entries.Count -eq 0 -or [string]::IsNullOrWhiteSpace($ListType)) {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Tenant Allow/Block List template '$Reference' has no entries or no list type and cannot be evaluated." -Sev 'Error'
        return @{ Current = $null }
    }

    $ExistingValues = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($ListItem in $ListItems) {
        if ("$($ListItem.ListType)" -eq $ListType -and -not [string]::IsNullOrWhiteSpace("$($ListItem.Value)")) {
            [void]$ExistingValues.Add("$($ListItem.Value)")
        }
    }

    $Missing = @($Entries | Where-Object { -not $ExistingValues.Contains($_) })

    $Current = [PSCustomObject]@{ missingEntries = @($Missing) }
    # Carried for the executor, not graded.
    $Current | Add-Member -NotePropertyName 'templateBody' -NotePropertyValue $Template

    @{
        Expected = [PSCustomObject]@{ missingEntries = @() }
        Current  = $Current
    }
}
