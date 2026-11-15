function Invoke-EditAdministrativeUnit {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Role.ReadWrite
    .DESCRIPTION
        Changes an administrative unit's name, description, visibility or membership, and adds or removes members
        of an assigned unit. Only the fields sent are changed. Switching to dynamic replaces the members with the
        rule's result. Restricted management cannot be changed after creation.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter.value ?? $Request.Body.tenantFilter
    # Object id of the administrative unit.
    $ID = $Request.Body.ID
    $Body = $Request.Body
    # Public or HiddenMembership.
    $Visibility = $Body.visibility.value ?? $Body.visibility
    # Assigned or Dynamic.
    $MembershipType = $Body.membershipType.value ?? $Body.membershipType
    # On or Paused: whether a dynamic rule is evaluated.
    $ProcessingState = $Body.membershipRuleProcessingState.value ?? $Body.membershipRuleProcessingState
    $MembershipRule = if ($null -ne $Body.membershipRule) { "$($Body.membershipRule)".Trim() }
    $DisplayName = if ($null -ne $Body.displayName) { "$($Body.displayName)".Trim() }
    # Users, groups or devices to add or remove, as picker objects or object ids. Assigned units only.
    $AddMembers = @($Body.AddMember).Where({ $_ })
    $RemoveMembers = @($Body.RemoveMember).Where({ $_ })
    $MemberCount = $AddMembers.Count + $RemoveMembers.Count

    $ValidationError = if ([string]::IsNullOrWhiteSpace($TenantFilter) -or $TenantFilter -eq 'AllTenants') {
        'tenantFilter is required and must be a single tenant'
    } elseif ([string]::IsNullOrWhiteSpace($ID) -or -not (Test-IsGuid -String $ID)) {
        'ID must be the object id of an administrative unit'
    } elseif ($null -ne $DisplayName -and $DisplayName -eq '') {
        'The display name cannot be empty'
    } elseif ($Visibility -and $Visibility -notin 'Public', 'HiddenMembership') {
        "Unsupported visibility '$Visibility'. Use Public or HiddenMembership"
    } elseif ($MembershipType -and $MembershipType -notin 'Assigned', 'Dynamic') {
        "Unsupported membership type '$MembershipType'. Use Assigned or Dynamic"
    } elseif ($ProcessingState -and $ProcessingState -notin 'On', 'Paused') {
        "Unsupported rule processing state '$ProcessingState'. Use On or Paused"
    } elseif ($MembershipType -eq 'Dynamic' -and [string]::IsNullOrWhiteSpace($MembershipRule)) {
        'A dynamic administrative unit needs a membership rule'
    } elseif ($MembershipType -eq 'Dynamic' -and $MemberCount -gt 0) {
        "A dynamic administrative unit's members come from its rule and cannot be changed by hand"
    } elseif (($AddMembers + $RemoveMembers).Where({ -not (Test-IsGuid -String ([string]($_.value ?? $_.id ?? $_))) }, 'First').Count -gt 0) {
        'Members must be given by object id'
    }
    if ($ValidationError) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = @(@{ resultText = "Error: $ValidationError"; state = 'error' }) }
            })
    }

    $Patch = [ordered]@{}
    if ($DisplayName) { $Patch.displayName = $DisplayName }
    if ($null -ne $Body.description) { $Patch.description = "$($Body.description)".Trim() }
    # Public is stored as no visibility; null clears HiddenMembership.
    if ($Visibility) { $Patch.visibility = if ($Visibility -eq 'HiddenMembership') { 'HiddenMembership' } else { $null } }
    if ($MembershipType -eq 'Dynamic') {
        $Patch.membershipType = 'Dynamic'
        $Patch.membershipRule = $MembershipRule
        $Patch.membershipRuleProcessingState = if ($ProcessingState) { $ProcessingState } else { 'On' }
    } elseif ($MembershipType -eq 'Assigned') {
        $Patch.membershipType = 'Assigned'
        $Patch.membershipRule = $null
        $Patch.membershipRuleProcessingState = $null
    } elseif ($ProcessingState) {
        $Patch.membershipRuleProcessingState = $ProcessingState
    }
    if ($Patch.Count -eq 0 -and $MemberCount -eq 0) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = @(@{ resultText = 'Error: Nothing to change'; state = 'error' }) }
            })
    }

    $Name = $DisplayName ?? $Body.currentDisplayName ?? $ID
    $Results = [System.Collections.Generic.List[object]]::new()
    $StatusCode = $null
    if ($Patch.Count -gt 0) {
        try {
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/directory/administrativeUnits/$ID" -tenantid $TenantFilter -type PATCH -body (ConvertTo-Json -InputObject $Patch -Compress)
            $Result = "Updated administrative unit '$Name'"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "$Result ($(@($Patch.Keys) -join ', '))" -Sev 'Info'
            $Results.Add(@{ resultText = $Result; state = 'success' })
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Result = "Failed to update administrative unit '$Name': $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error' -LogData $ErrorMessage
            $Results.Add(@{ resultText = $Result; state = 'error' })
            # With no member changes the unit update is the whole request, so its upstream status is the answer.
            if ($MemberCount -eq 0) { $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_ }
        }
    }
    if ($AddMembers.Count -gt 0) {
        $Results.AddRange([object[]]@(Set-CIPPAdministrativeUnitMember -TenantFilter $TenantFilter -UnitId $ID -UnitName $Name -Action 'Add' -Members $AddMembers -Headers $Headers -APIName $APIName))
    }
    if ($RemoveMembers.Count -gt 0) {
        $Results.AddRange([object[]]@(Set-CIPPAdministrativeUnitMember -TenantFilter $TenantFilter -UnitId $ID -UnitName $Name -Action 'Remove' -Members $RemoveMembers -Headers $Headers -APIName $APIName))
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode ?? (Get-CippBulkStatusCode -Total $Results.Count -Failed @($Results.Where({ $_.state -eq 'error' })).Count)
            Body       = @{ Results = @($Results) }
        })
}
