function Invoke-ExecRefreshMyAccess {
    <#
    .SYNOPSIS
        Re-check the caller's Entra group membership and refresh their CIPP roles
    .DESCRIPTION
        Clears the caller's cached role resolution and re-checks Entra group membership, so a
        just-activated PIM group grants its mapped CIPP role without waiting out the role cache.
        Only ever refreshes the calling user's own access.
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Public
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # A user whose PIM elevation has not landed yet holds no CIPP role at all, so any role gate
    # would lock them out of the one endpoint meant to fix exactly that. The role check is
    # skipped (Public) and identity comes exclusively from the platform-injected principal
    # header, never from the request body, so the caller can only refresh themselves.
    $User = $null
    try {
        $PrincipalHeader = $Request.Headers.'x-ms-client-principal'
        if (-not [string]::IsNullOrEmpty($PrincipalHeader)) {
            $User = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($PrincipalHeader)) | ConvertFrom-Json
        }
    } catch {
        $User = $null
    }

    if ($User -and $User.claims -and [string]::IsNullOrWhiteSpace($User.userDetails)) {
        $Claims = @($User.claims)
        $Upn = ($Claims | Where-Object { $_.typ -in @('preferred_username', 'upn', 'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn', 'email', 'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress') } | Select-Object -First 1).val
        if ([string]::IsNullOrWhiteSpace($Upn)) { $Upn = $Request.Headers.'x-ms-client-principal-name' }
    } else {
        $Upn = $User.userDetails
    }

    # App-only API clients authenticate as an app registration (a GUID principal name) and have
    # no group membership to refresh.
    $IsApiClient = $Request.Headers.'x-ms-client-principal-idp' -eq 'aad' -and $Request.Headers.'x-ms-client-principal-name' -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

    if ($IsApiClient -or [string]::IsNullOrWhiteSpace($Upn)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Unauthorized
                Body       = @{ Results = 'Access refresh is only available to a signed-in user.' }
            })
    }

    try {
        $Table = Get-CippTable -TableName 'cacheAccessUserRoles'
        $SafeUpn = $Upn -replace "'", "''"

        # A refresh costs a Graph membership lookup plus a full group sync, so cap how often a
        # single user can trigger one.
        $CooldownSeconds = 30
        $CooldownMarker = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'AccessRefresh' and RowKey eq '$SafeUpn'"
        if ($CooldownMarker.Timestamp) {
            $SecondsSince = ((Get-Date).ToUniversalTime() - $CooldownMarker.Timestamp.UtcDateTime).TotalSeconds
            if ($SecondsSince -lt $CooldownSeconds) {
                $WaitSeconds = [math]::Ceiling($CooldownSeconds - $SecondsSince)
                Write-LogMessage -API 'RefreshMyAccess' -headers $Request.Headers -message "$Upn hit the access-refresh cooldown; returned 429 asking them to retry in $WaitSeconds seconds." -sev Info
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::TooManyRequests
                        Body       = @{ Results = "Your access was refreshed less than $CooldownSeconds seconds ago. Try again in $WaitSeconds seconds." }
                    })
            }
        }
        Add-CIPPAzDataTableEntity @Table -Entity @{ PartitionKey = 'AccessRefresh'; RowKey = [string]$Upn } -Force | Out-Null

        # Drop the caller's cached role resolution so the re-check below goes to Graph instead
        # of reading the row back.
        $CachedRole = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'AccessUser' and RowKey eq '$SafeUpn'"
        if ($CachedRole) {
            Remove-CIPPAzDataTableEntity -Force @Table -Entity $CachedRole
        }

        # Seeds the same placeholder roles Test-CIPPAccess does, so the rewritten cache row
        # matches what normal resolution would produce.
        $Resolved = Test-CIPPAccessUserRole -User ([PSCustomObject]@{
                userDetails = [string]$Upn
                userRoles   = @('authenticated', 'anonymous')
            })
        $GroupRoles = @($Resolved.userRoles | Where-Object { $_ -notin @('authenticated', 'anonymous') })

        # Refresh the allowedUsers projection CRAFT authenticates against and drop its
        # in-memory user cache, so the next request carries the new roles.
        try { Start-UserSyncTimer } catch {}
        try { [Craft.Services.AuthBridge]::InvalidateUsers() } catch {}

        if (($GroupRoles | Measure-Object).Count -gt 0) {
            $Result = "Access refreshed. Roles from your Entra group memberships: $($GroupRoles -join ', ')."
        } else {
            $Result = 'Access refreshed, but none of your Entra group memberships map to a CIPP role. If you activated a group with PIM just now, the change may not have reached Microsoft Graph yet - wait a moment and refresh again.'
        }
        $RolesText = if (($GroupRoles | Measure-Object).Count -gt 0) { $GroupRoles -join ', ' } else { 'none' }
        Write-LogMessage -API 'RefreshMyAccess' -headers $Request.Headers -message "$Upn refreshed their access. Group-mapped roles: $RolesText" -sev Info
        $StatusCode = [HttpStatusCode]::OK
        $Body = @{ Results = $Result; Roles = $GroupRoles }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'RefreshMyAccess' -headers $Request.Headers -message "Failed to refresh access for $Upn. $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Body = @{ Results = "Failed to refresh access: $($ErrorMessage.NormalizedError)" }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
