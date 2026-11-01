function Get-CIPPBaselineEnrollmentRestrictionTemplateState {
    <#
    .SYNOPSIS
        Prepare hook for EnrollmentRestrictionTemplate: is this instance's restriction deployed
        and in sync with its template.
    .DESCRIPTION
        One instance grades ONE template, resolved from PartitionKey
        'EnrollmentRestrictionTemplate' by RowKey. The tenant's restrictions come from the
        IntuneDeviceEnrollmentConfigurations cache and are grouped the way the portal shows them
        (both Android objects as one) by ConvertFrom-CIPPEnrollmentRestrictionConfiguration.

        Graded: deployed (every object the platform needs exists) and the platform settings
        through Get-CIPPEnrollmentRestrictionProjection. Priority is not graded: it is relative to
        each tenant's other restrictions and is only applied when the restriction is created.

        The assignment grades separately through Compare-CIPPIntuneAssignments, which resolves
        group names the same way Set-CIPPAssignedPolicy writes them. It is left out when the
        template does not assign ('On'), when the cache row carries no assignments property (a
        failed assignment read is not the same as unassigned) and when the comparison could not
        be completed - a deviation no run can clear is worse than a blind spot.
        The template and the matched object ids ride along on Current for the executor.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Configurations = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'IntuneDeviceEnrollmentConfigurations')
    if ($Configurations.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'IntuneDeviceEnrollmentConfigurations')) {
        return @{ Current = $null }
    }

    $Reference = $Item.Variables.enrollmentRestrictionTemplate
    if ($Reference -is [System.Management.Automation.PSCustomObject] -and $Reference.PSObject.Properties.Name -contains 'value') { $Reference = $Reference.value }
    if ([string]::IsNullOrWhiteSpace("$Reference")) { return @{ Current = $null } }

    $Table = Get-CippTable -tablename 'templates'
    $SafeReference = ConvertTo-CIPPODataFilterValue -Value "$Reference"
    $Entity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'EnrollmentRestrictionTemplate' and RowKey eq '$SafeReference'" | Select-Object -First 1
    $Template = $(if ($Entity -and -not [string]::IsNullOrWhiteSpace($Entity.JSON)) {
            try { ConvertTo-CIPPEnrollmentRestrictionSettings -InputObject ($Entity.JSON | ConvertFrom-Json -Depth 20 -ErrorAction Stop) } catch { $null }
        })
    if (-not $Template -or [string]::IsNullOrWhiteSpace($Template.displayName) -or [string]::IsNullOrWhiteSpace($Template.platform)) { return @{ Current = $null } }

    $Existing = @(ConvertFrom-CIPPEnrollmentRestrictionConfiguration -Configurations $Configurations) |
        Where-Object { $_.displayName -eq $Template.displayName -and $_.platform -eq $Template.platform } | Select-Object -First 1

    $Expected = Get-CIPPEnrollmentRestrictionProjection -Settings $Template -Platform $Template.platform
    $Current = Get-CIPPEnrollmentRestrictionProjection -Settings $Existing -Platform $Template.platform
    $Expected | Add-Member -NotePropertyName 'deployed' -NotePropertyValue $true
    $Current | Add-Member -NotePropertyName 'deployed' -NotePropertyValue ($null -ne $Existing -and $Existing.missingPlatformTypes.Count -eq 0)

    if ($null -ne $Existing -and $Existing.assignmentsKnown -and (Get-CIPPIntuneAssignTarget -AssignTo $Template.AssignTo).Managed) {
        try {
            $AssignmentDetail = Compare-CIPPIntuneAssignments -ExistingAssignments @($Existing.assignments) -ExpectedAssignTo $Template.AssignTo -ExpectedCustomGroup "$($Template.customGroup)" -PolicyType 'deviceEnrollmentConfigurations' -TenantFilter $TenantFilter
            if (-not $AssignmentDetail.Unknown) {
                $Expected | Add-Member -NotePropertyName 'isAssigned' -NotePropertyValue $true
                $Current | Add-Member -NotePropertyName 'isAssigned' -NotePropertyValue ([bool]$AssignmentDetail.Matched)
            }
        } catch {
            Write-Information "Baselines: EnrollmentRestrictionTemplate assignment compare failed: $($_.Exception.Message)"
        }
    }

    # Carried for the executor, not graded.
    $Current | Add-Member -NotePropertyMembers ([ordered]@{ template = $Template; existingIds = @($Existing.ids) })

    @{ Expected = $Expected; Current = $Current }
}
