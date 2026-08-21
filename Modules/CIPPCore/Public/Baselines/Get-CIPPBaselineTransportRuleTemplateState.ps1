function Get-CIPPBaselineTransportRuleTemplateState {
    <#
    .SYNOPSIS
        Prepare hook for TransportRuleTemplate: is this instance's transport rule deployed.
    .DESCRIPTION
        One instance grades ONE template - the baseline stores an instance per selected
        template (instanceIdentity), so the hook resolves a single reference.

        Reports the pair the classic standard reported - the rule the template names, and
        whether it is missing from the tenant. It compares PRESENCE BY NAME and nothing
        else: the classic never diffed rule bodies, and a transport rule is arbitrary schema
        that operators tune by hand, so grading fields it never compared would report drift
        on every hand-edit.

        Template resolution is deliberately written out here rather than shared. The
        families differ: this one looks templates up by RowKey ALONE under PartitionKey
        'TransportTemplate', with no GUID or displayName fallback, and it keys the rule on
        the payload's 'name'. Borrowing another family's lookup would silently change which
        template resolves.

        Names are matched against Identity, DisplayName and Name, because Exchange returns
        the rule under different ones depending on how it was created - the classic built
        its set from Identity and DisplayName for the same reason.

        A template reference that resolves to nothing reports No Data. The classic
        'continue'd past it and read as compliant; under the instance model the template IS
        the instance, so a deleted template means the standard cannot evaluate.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Rules = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoTransportRules')
    if ($Rules.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'ExoTransportRules')) {
        return @{ Current = $null }
    }

    # The picker stores either a plain id or a { label, value } object depending on how the
    # baseline was saved - the classic filtered on $_.value for exactly that reason.
    $Reference = $Item.Variables.transportRuleTemplate
    if ($Reference -is [System.Management.Automation.PSCustomObject] -and $Reference.PSObject.Properties.Name -contains 'value') { $Reference = $Reference.value }
    if ([string]::IsNullOrWhiteSpace("$Reference")) { return @{ Current = $null } }

    $Table = Get-CippTable -tablename 'templates'
    $SafeReference = ConvertTo-CIPPODataFilterValue -Value "$Reference"
    $Entity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'TransportTemplate' and RowKey eq '$SafeReference'" | Select-Object -First 1
    $Body = $(if ($Entity -and -not [string]::IsNullOrWhiteSpace($Entity.JSON)) { try { $Entity.JSON | ConvertFrom-Json -Depth 20 -ErrorAction Stop } catch { $null } })
    $RuleName = "$($Body.name)"
    if (-not $Body -or [string]::IsNullOrWhiteSpace($RuleName)) { return @{ Current = $null } }

    $Deployed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Rule in $Rules) {
        foreach ($Candidate in @("$($Rule.Identity)", "$($Rule.DisplayName)", "$($Rule.Name)")) {
            if (-not [string]::IsNullOrWhiteSpace($Candidate)) { [void]$Deployed.Add($Candidate) }
        }
    }
    $IsDeployed = $Deployed.Contains($RuleName)

    $Current = [PSCustomObject]@{
        deployedTransportRules = @(if ($IsDeployed) { $RuleName })
        missingTransportRules  = @(if (-not $IsDeployed) { $RuleName })
    }
    # Carried for the executor, not graded.
    $Current | Add-Member -NotePropertyName 'ruleBodies' -NotePropertyValue @($Body)
    $Current | Add-Member -NotePropertyName 'deployedNames' -NotePropertyValue @(if ($IsDeployed) { $RuleName })

    @{
        Expected = [PSCustomObject]@{
            deployedTransportRules = @($RuleName)
            missingTransportRules  = @()
        }
        Current  = $Current
    }
}
