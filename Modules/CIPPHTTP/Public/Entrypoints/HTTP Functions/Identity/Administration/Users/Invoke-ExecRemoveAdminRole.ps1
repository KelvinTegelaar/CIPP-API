function Invoke-ExecRemoveAdminRole {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Role.ReadWrite

    .DESCRIPTION
        Removes a user from an assigned Microsoft Entra admin role.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter.value ?? $Request.Body.tenantFilter
    $RoleId = $Request.Body.RoleId.value ?? $Request.Body.RoleId
    $RoleName = $Request.Body.RoleName.label ?? $Request.Body.RoleName.value ?? $Request.Body.RoleName
    $Users = if ($Request.Body.Users) { @($Request.Body.Users) } else { @() }

    # Input validation
    if ([string]::IsNullOrWhiteSpace($TenantFilter) -or [string]::IsNullOrWhiteSpace($RoleId) -or $Users.Count -eq 0) {
        $Result = 'TenantFilter, RoleId, and Users are required to remove an admin role assignment.'
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error'
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::BadRequest
            Body       = @{ 'Results' = @($Result) }
        }
    }

    $Results = [System.Collections.Generic.List[string]]::new()
    $Failures = 0

    foreach ($User in $Users) {
        # Handle both roles and view user pages where user info is in different properties
        $UserId = $User.value ?? $User.id ?? $User.UserId ?? $User
        $UserName = $User.addedFields.userPrincipalName ?? $User.addedFields.displayName ?? $User.userPrincipalName ?? $User.displayName ?? $User.label ?? $User.UserName ?? $UserId

        if ([string]::IsNullOrWhiteSpace($UserId)) {
            $Failures++
            $Result = "Skipped a $RoleName role removal request because UserId was empty."
            $Results.Add($Result)
            Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error'
            continue
        }

        try {
            $null = New-GraphPOSTRequest -type DELETE -uri "https://graph.microsoft.com/v1.0/directoryRoles/$RoleId/members/$UserId/`$ref" -tenantid $TenantFilter
            $Result = "Successfully removed $UserName from admin role $RoleName."
            $Results.Add($Result)
            Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Info'
        } catch {
            $Failures++
            $ErrorMessage = Get-CippException -Exception $_
            $Result = "Failed to remove $UserName from admin role $RoleName. $($ErrorMessage.NormalizedError)"
            $Results.Add($Result)
            Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error' -LogData $ErrorMessage
        }
    }

    $StatusCode = $Failures -gt 0 ? [HttpStatusCode]::InternalServerError : [HttpStatusCode]::OK

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @{ 'Results' = @($Results) }
    }
}
