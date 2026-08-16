function Get-CIPPBaselineGroupTemplateState {
    <#
    .SYNOPSIS
        Prepare hook for GroupTemplate: is this instance's group deployed.
    .DESCRIPTION
        One instance grades ONE template. Grades PRESENCE BY NAME only, matching the
        classic's report - group settings drift is repaired by the executor's update branch
        on every remediation run (checkBeforeRun:false on the definition), exactly as the
        classic's remediation loop did.

        Dynamic distribution groups are Exchange objects, not Graph groups, so their
        presence is checked against the ExoDynamicDistributionGroup cache by Name; every
        other group type checks the Groups cache by displayName. That split is the classic's
        own.

        Template resolution stays per-family: PartitionKey 'GroupTemplate', RowKey alone.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Reference = $Item.Variables.groupTemplate
    if ($Reference -is [System.Management.Automation.PSCustomObject] -and $Reference.PSObject.Properties.Name -contains 'value') { $Reference = $Reference.value }
    if ([string]::IsNullOrWhiteSpace("$Reference")) { return @{ Current = $null } }

    $Table = Get-CippTable -tablename 'templates'
    $SafeReference = ConvertTo-CIPPODataFilterValue -Value "$Reference"
    $Entity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'GroupTemplate' and RowKey eq '$SafeReference'" | Select-Object -First 1
    $Template = $(if ($Entity -and -not [string]::IsNullOrWhiteSpace($Entity.JSON)) { try { $Entity.JSON | ConvertFrom-Json -Depth 20 -ErrorAction Stop } catch { $null } })
    $GroupName = "$($Template.displayName)"
    if (-not $Template -or [string]::IsNullOrWhiteSpace($GroupName)) { return @{ Current = $null } }

    if ("$($Template.groupType)" -eq 'dynamicDistribution') {
        $Distros = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoDynamicDistributionGroup')
        if ($Distros.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'ExoDynamicDistributionGroup')) {
            return @{ Current = $null }
        }
        $Existing = $Distros | Where-Object { "$($_.Name)" -eq $GroupName } | Select-Object -First 1
    } else {
        $Groups = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'Groups')
        if ($Groups.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'Groups')) {
            return @{ Current = $null }
        }
        $Existing = $Groups | Where-Object { "$($_.displayName)" -eq $GroupName } | Select-Object -First 1
    }

    $Current = [PSCustomObject]@{ deployed = [bool]$Existing }
    # Carried for the executor, not graded.
    $Current | Add-Member -NotePropertyName 'templateBody' -NotePropertyValue $Template
    $Current | Add-Member -NotePropertyName 'existingGroup' -NotePropertyValue $Existing

    @{
        Expected = [PSCustomObject]@{ deployed = $true }
        Current  = $Current
    }
}
