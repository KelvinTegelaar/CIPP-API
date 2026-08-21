function Invoke-CIPPBaselineAssignmentFilterTemplate {
    <#
    .SYNOPSIS
        AssignmentFilterTemplate executor: creates the filter or patches the drifted fields.
    .DESCRIPTION
        Create goes through New-CIPPAssignmentFilter, the same path the classic and the
        assignment filter UI use. Update PATCHes only the fields that differ - description,
        platform, rule, assignmentFilterManagementType - matching the classic's field-level
        update; displayName is the identity and is never rewritten.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Template = $Current.templateBody
    if (-not $Template) { return }

    if (-not $Current.existingId) {
        $Result = New-CIPPAssignmentFilter -FilterObject $Template -TenantFilter $TenantFilter -APIName 'Baselines'
        if ($Result.Success -ne $true) {
            throw "Failed to create assignment filter '$($Template.displayName)': $($Result.Message)"
        }
        return
    }

    $PatchBody = [PSCustomObject]@{}
    foreach ($Field in @('description', 'platform', 'rule', 'assignmentFilterManagementType')) {
        if ("$($Current.$Field)" -ne "$($Template.$Field)") {
            $PatchBody | Add-Member -NotePropertyName $Field -NotePropertyValue $Template.$Field
        }
    }
    if (@($PatchBody.PSObject.Properties).Count -eq 0) { return }

    $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters/$($Current.existingId)" -tenantid $TenantFilter -type PATCH -body (ConvertTo-Json -InputObject $PatchBody -Depth 10)
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Updated assignment filter '$($Template.displayName)'." -Sev 'Info'
}
