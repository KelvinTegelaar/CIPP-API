function Invoke-AddAdministrativeUnit {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Role.ReadWrite
    .DESCRIPTION
        Creates an administrative unit. Membership is assigned by hand or kept by a dynamic rule over users or
        devices (Entra ID P1). Restricted management can only be chosen here: Graph does not let it change after
        the unit exists. An assigned unit can be given its first users, groups and devices in the same request.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter.value ?? $Request.Body.tenantFilter
    $DisplayName = "$($Request.Body.displayName)".Trim()
    $Description = "$($Request.Body.description)".Trim()
    # Public or HiddenMembership (only members and roles scoped to the unit see who is in it).
    $Visibility = $Request.Body.visibility.value ?? $Request.Body.visibility
    if ([string]::IsNullOrWhiteSpace($Visibility)) { $Visibility = 'Public' }
    # Assigned or Dynamic.
    $MembershipType = $Request.Body.membershipType.value ?? $Request.Body.membershipType
    if ([string]::IsNullOrWhiteSpace($MembershipType)) { $MembershipType = 'Assigned' }
    # Dynamic membership rule, such as (user.department -eq "Sales"). Required for a dynamic unit.
    $MembershipRule = "$($Request.Body.membershipRule)".Trim()
    # Restricted management: only roles scoped to the unit can manage its members, not tenant-wide admins.
    $IsMemberManagementRestricted = [bool]($Request.Body.isMemberManagementRestricted -eq $true -or "$($Request.Body.isMemberManagementRestricted)" -eq 'true')
    # Users, groups or devices to add once the unit exists, as picker objects or object ids. Assigned units only.
    $Members = @($Request.Body.members).Where({ $_ })

    $ValidationError = if ([string]::IsNullOrWhiteSpace($TenantFilter) -or $TenantFilter -eq 'AllTenants') {
        'tenantFilter is required and must be a single tenant'
    } elseif ([string]::IsNullOrWhiteSpace($DisplayName)) {
        'A display name is required'
    } elseif ($Visibility -notin 'Public', 'HiddenMembership') {
        "Unsupported visibility '$Visibility'. Use Public or HiddenMembership"
    } elseif ($MembershipType -notin 'Assigned', 'Dynamic') {
        "Unsupported membership type '$MembershipType'. Use Assigned or Dynamic"
    } elseif ($MembershipType -eq 'Dynamic' -and [string]::IsNullOrWhiteSpace($MembershipRule)) {
        'A dynamic administrative unit needs a membership rule'
    } elseif ($MembershipType -eq 'Dynamic' -and $Members.Count -gt 0) {
        "A dynamic administrative unit's members come from its rule and cannot be added by hand"
    } elseif ($Members.Where({ -not (Test-IsGuid -String ([string]($_.value ?? $_.id ?? $_))) }, 'First').Count -gt 0) {
        'Members must be given by object id'
    }
    if ($ValidationError) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = @(@{ resultText = "Error: $ValidationError"; state = 'error' }) }
            })
    }

    $Unit = [ordered]@{
        displayName                  = $DisplayName
        isMemberManagementRestricted = $IsMemberManagementRestricted
    }
    if ($Description) { $Unit.description = $Description }
    # Graph models a public unit as no visibility at all.
    if ($Visibility -eq 'HiddenMembership') { $Unit.visibility = 'HiddenMembership' }
    if ($MembershipType -eq 'Dynamic') {
        $Unit.membershipType = 'Dynamic'
        $Unit.membershipRule = $MembershipRule
        $Unit.membershipRuleProcessingState = 'On'
    }

    try {
        $NewUnit = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/directory/administrativeUnits' -tenantid $TenantFilter -type POST -body (ConvertTo-Json -InputObject $Unit -Compress)
        $Result = "Created administrative unit '$DisplayName'"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "$Result (id $($NewUnit.id))" -Sev 'Info'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to create administrative unit '$DisplayName': $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{
                StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
                Body       = @{ Results = @(@{ resultText = $Result; state = 'error' }) }
            })
    }

    # The unit exists whatever happens to its members, so a failed member is reported but never fails the request.
    $MemberResults = if ($Members.Count -gt 0) {
        Set-CIPPAdministrativeUnitMember -TenantFilter $TenantFilter -UnitId $NewUnit.id -UnitName $DisplayName -Action 'Add' -Members $Members -Headers $Headers -APIName $APIName
    }
    $Results = @(@{ resultText = $Result; state = 'success' }) + @($MemberResults)

    return ([HttpResponseContext]@{
            StatusCode = if ($Results.Where({ $_.state -eq 'error' }, 'First').Count -gt 0) { [HttpStatusCode]::MultiStatus } else { [HttpStatusCode]::OK }
            Body       = @{ Results = $Results }
        })
}
