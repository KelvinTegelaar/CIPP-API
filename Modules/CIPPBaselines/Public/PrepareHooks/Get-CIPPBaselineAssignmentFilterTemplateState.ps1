function Get-CIPPBaselineAssignmentFilterTemplateState {
    <#
    .SYNOPSIS
        Prepare hook for AssignmentFilterTemplate: is this instance's filter deployed and in
        sync.
    .DESCRIPTION
        One instance grades ONE template. Matched on displayName, and unlike most template
        families this one grades the WRITABLE FIELDS too - description, platform, rule and
        assignmentFilterManagementType - because the classic's remediation already did a
        field-level diff before patching, so the graded compare and the write agree.

        When the filter is missing only presence is graded; grading fields against a filter
        that does not exist would report one drift row per field where a single 'missing' is
        the truth.

        The classic's own aggregate compare was broken - its Where-Object tested
        $_.displayName against itself, so anything deployed made everything read deployed.
        The per-field compare here is what its remediation actually enforced.

        Template resolution stays per-family: PartitionKey 'AssignmentFilterTemplate',
        RowKey alone.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Filters = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'IntuneAssignmentFilters')
    if ($Filters.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'IntuneAssignmentFilters')) {
        return @{ Current = $null }
    }

    $Reference = $Item.Variables.assignmentFilterTemplate
    if ($Reference -is [System.Management.Automation.PSCustomObject] -and $Reference.PSObject.Properties.Name -contains 'value') { $Reference = $Reference.value }
    if ([string]::IsNullOrWhiteSpace("$Reference")) { return @{ Current = $null } }

    $Table = Get-CippTable -tablename 'templates'
    $SafeReference = ConvertTo-CIPPODataFilterValue -Value "$Reference"
    $Entity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'AssignmentFilterTemplate' and RowKey eq '$SafeReference'" | Select-Object -First 1
    $Template = $(if ($Entity -and -not [string]::IsNullOrWhiteSpace($Entity.JSON)) { try { $Entity.JSON | ConvertFrom-Json -Depth 20 -ErrorAction Stop } catch { $null } })
    $FilterName = "$($Template.displayName)"
    if (-not $Template -or [string]::IsNullOrWhiteSpace($FilterName)) { return @{ Current = $null } }

    $Existing = $Filters | Where-Object { "$($_.displayName)" -eq $FilterName } | Select-Object -First 1

    if (-not $Existing) {
        $Current = [PSCustomObject]@{ deployed = $false }
        $Current | Add-Member -NotePropertyName 'templateBody' -NotePropertyValue $Template
        $Current | Add-Member -NotePropertyName 'existingId' -NotePropertyValue $null
        return @{
            Expected = [PSCustomObject]@{ deployed = $true }
            Current  = $Current
        }
    }

    $Expected = [PSCustomObject]@{
        deployed                       = $true
        description                    = "$($Template.description)"
        platform                       = "$($Template.platform)"
        rule                           = "$($Template.rule)"
        assignmentFilterManagementType = "$($Template.assignmentFilterManagementType)"
    }
    $Current = [PSCustomObject]@{
        deployed                       = $true
        description                    = "$($Existing.description)"
        platform                       = "$($Existing.platform)"
        rule                           = "$($Existing.rule)"
        assignmentFilterManagementType = "$($Existing.assignmentFilterManagementType)"
    }
    # Carried for the executor, not graded.
    $Current | Add-Member -NotePropertyName 'templateBody' -NotePropertyValue $Template
    $Current | Add-Member -NotePropertyName 'existingId' -NotePropertyValue "$($Existing.id)"

    @{ Expected = $Expected; Current = $Current }
}
