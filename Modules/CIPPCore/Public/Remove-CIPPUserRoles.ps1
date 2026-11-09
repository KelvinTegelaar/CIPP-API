function Remove-CIPPUserRoles {
    <#
    .SYNOPSIS
        Removes every directory (admin) role assignment a user holds.

    .DESCRIPTION
        The "remove all admin roles" step of offboarding. The user's assignments are read through
        Get-CIPPPIMRoleAssignments, so built-in and custom roles, administrative-unit scopes and PIM
        eligible or active assignments are all seen, and each one is removed:
          - On a PIM-licensed tenant through Invoke-CIPPPIMAssignmentAction, the single write path for
            role assignments, which also refuses to remove the last active Global Administrator.
          - Elsewhere with a direct delete of the unified role assignment, guarded by the same
            last-Global-Administrator check.

        Assignments the user holds through a role-assignable group are left alone and reported: the
        group's assignment is the real one, and the group removal step takes the user out of the group.

        Returns one line per assignment. Failures start with 'Failed', which is what the offboarding
        progress view uses to mark the step as failed.

    .PARAMETER UserID
        Object id of the user. Resolved from Username when not supplied.

    .PARAMETER Username
        userPrincipalName of the user, used in the result text and logs.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Username,
        $TenantFilter,
        $APIName = 'Remove User Roles',
        $Headers,
        $UserID
    )

    $GlobalAdminTemplateId = '62e90394-69f5-4237-9190-012177145e10'
    $Results = [System.Collections.Generic.List[string]]::new()

    try {
        if (-not $UserID) {
            # Guest UPNs contain '#EXT#'; unencoded, the '#' starts a URI fragment and truncates the Graph path.
            $EncodedUser = [System.Uri]::EscapeDataString($Username)
            $UserID = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($EncodedUser)?`$select=id" -tenantid $TenantFilter).id
        }
        $Rows = @(Get-CIPPPIMRoleAssignments -TenantFilter $TenantFilter -PrincipalId $UserID)
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to list role assignments for $Username`: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error' -LogData $ErrorMessage
        return $Message
    }

    if ($Rows.Count -eq 0) {
        $Message = "$Username has no directory role assignments."
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
        return $Message
    }

    # Eligibilities go last: removing one also retires an activation made from it, and that
    # activation is reported on its own line first.
    $Rows = @($Rows | Sort-Object -Stable -Property @{ Expression = { if ($_.AssignmentType -eq 'Eligible') { 1 } else { 0 } } })

    Write-Information "Removing $($Rows.Count) role assignment(s) from $Username in $TenantFilter"

    foreach ($Row in $Rows) {
        $RoleName = $Row.RoleDisplayName ?? $Row.RoleDefinitionId
        $Kind = switch ([string]$Row.AssignmentType) {
            'Eligible' { 'eligible' }
            'Active' { 'time-bound active' }
            'ActivatedFromEligible' { 'activated' }
            default { 'permanent' }
        }
        $Scope = if ($Row.DirectoryScopeId -and $Row.DirectoryScopeId -ne '/') { " scoped to $($Row.DirectoryScopeId)" } else { '' }
        $Label = "$Kind $RoleName assignment$Scope"

        if ($Row.MemberType -eq 'Group') {
            $Message = "Skipped the $Label for $Username because it is inherited through a role-assignable group. The group removal step takes the user out of that group."
            $Results.Add($Message)
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
            continue
        }

        try {
            if ($Row.PIMCapable) {
                $null = Invoke-CIPPPIMAssignmentAction -TenantFilter $TenantFilter -Action 'Remove' -PrincipalId $UserID -RoleDefinitionId $Row.RoleDefinitionId -DirectoryScopeId ([string]$Row.DirectoryScopeId) -AssignmentType ([string]$Row.AssignmentType) -Justification 'Removed during offboarding via CIPP' -Headers $Headers -APIName $APIName
            } else {
                if ($Row.RoleDefinitionId -eq $GlobalAdminTemplateId) {
                    $OtherAdmins = @(Get-CIPPPIMRoleAssignments -TenantFilter $TenantFilter -RoleDefinitionId $GlobalAdminTemplateId | Where-Object { $_.PrincipalId -ne $UserID })
                    if ($OtherAdmins.Count -eq 0) {
                        throw "$Username is the last Global Administrator in $TenantFilter. Assign another Global Administrator first."
                    }
                }
                $Uri = if ($Row.RoleAssignmentId) {
                    "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments/$($Row.RoleAssignmentId)"
                } else {
                    "https://graph.microsoft.com/v1.0/directoryRoles(roleTemplateId='$($Row.RoleDefinitionId)')/members/$UserID/`$ref"
                }
                $null = New-GraphPOSTRequest -type DELETE -uri $Uri -tenantid $TenantFilter
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Removed the $Label from $Username" -Sev 'Info'
            }
            $Results.Add("Successfully removed the $Label from $Username")
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Message = "Failed to remove the $Label from $Username`: $($ErrorMessage.NormalizedError)"
            $Results.Add($Message)
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error' -LogData $ErrorMessage
        }
    }

    return $Results
}
