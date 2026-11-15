function Invoke-ExecAdministrativeUnitMembers {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Role.ReadWrite
    .DESCRIPTION
        Adds users, groups or devices to an administrative unit, or removes them. Adding a group adds the group
        itself, not its members. A dynamic unit's members come from its rule and cannot be changed by hand.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter.value ?? $Request.Body.tenantFilter
    # addMember or removeMember.
    $Action = $Request.Body.action.value ?? $Request.Body.action
    # Object id of the administrative unit.
    $ID = $Request.Body.ID
    $UnitName = $Request.Body.displayName ?? $ID
    # Object ids of the users, groups or devices; picker objects carry the id in value and the name in label.
    $Members = @(foreach ($Member in @($Request.Body.members)) {
            if (-not $Member) { continue }
            $MemberId = $Member.value ?? $Member.id ?? $Member
            [PSCustomObject]@{ id = [string]$MemberId; name = [string]($Member.label ?? $Member.displayName ?? $MemberId) }
        })

    $ValidationError = if ([string]::IsNullOrWhiteSpace($TenantFilter) -or $TenantFilter -eq 'AllTenants') {
        'tenantFilter is required and must be a single tenant'
    } elseif ($Action -notin 'addMember', 'removeMember') {
        "Unsupported action '$Action'. Use addMember or removeMember"
    } elseif ([string]::IsNullOrWhiteSpace($ID) -or -not (Test-IsGuid -String $ID)) {
        'ID must be the object id of an administrative unit'
    } elseif ($Members.Count -eq 0) {
        'Select at least one member'
    } elseif (@($Members.Where({ -not (Test-IsGuid -String $_.id) })).Count -gt 0) {
        'Members must be given by object id'
    }
    if ($ValidationError) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = @(@{ resultText = "Error: $ValidationError"; state = 'error' }) }
            })
    }

    $MemberAction = if ($Action -eq 'addMember') { 'Add' } else { 'Remove' }
    $Results = @(Set-CIPPAdministrativeUnitMember -TenantFilter $TenantFilter -UnitId $ID -UnitName $UnitName -Action $MemberAction -Members $Members -Headers $Headers -APIName $APIName)

    return ([HttpResponseContext]@{
            StatusCode = Get-CippBulkStatusCode -Total $Results.Count -Failed @($Results.Where({ $_.state -eq 'error' })).Count
            Body       = @{ Results = $Results }
        })
}
