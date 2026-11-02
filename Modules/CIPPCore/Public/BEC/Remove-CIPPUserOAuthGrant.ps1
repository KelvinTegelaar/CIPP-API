function Remove-CIPPUserOAuthGrant {
    <#
    .SYNOPSIS
        Deletes a user's OAuth consent grants and app-role assignments.
    .DESCRIPTION
        Removes the delegated consent grants (oauth2PermissionGrants) and enterprise-app role
        assignments identified by id. Removing a grant revokes that consent only; it does not disable
        the application for other users and existing access tokens keep working until they expire, so
        pair it with a session revocation.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER UserId
        The user's object id (needed for app-role assignment deletes).
    .PARAMETER GrantIds
        oauth2PermissionGrant ids to delete.
    .PARAMETER AppRoleAssignmentIds
        appRoleAssignment ids to delete.
    .PARAMETER Headers
        CIPP request headers for logging.
    .PARAMETER APIName
        Logging API name.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [string]$UserId,
        [string[]]$GrantIds = @(),
        [string[]]$AppRoleAssignmentIds = @(),
        $Headers,
        [string]$APIName = 'BECRemediate'
    )

    $Sets = @(
        @{ Ids = $GrantIds; Uri = 'oauth2PermissionGrants/{0}'; Noun = 'consent grant'; NeedsUser = $false }
        @{ Ids = $AppRoleAssignmentIds; Uri = "users/$UserId/appRoleAssignments/{0}"; Noun = 'app-role assignment'; NeedsUser = $true }
    )
    $Results = [System.Collections.Generic.List[object]]::new()
    foreach ($Set in $Sets) {
        foreach ($Id in @($Set.Ids | Where-Object { $_ })) {
            if ($Set.NeedsUser -and -not $UserId) {
                $Results.Add([pscustomobject]@{ Target = $Id; state = 'error'; resultText = "The user object id is required to remove an $($Set.Noun)" })
                continue
            }
            if (-not $PSCmdlet.ShouldProcess($Id, "Delete $($Set.Noun)")) { continue }
            try {
                $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/$($Set.Uri -f $Id)" -tenantid $TenantFilter -type DELETE -AsApp $true
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Deleted $($Set.Noun) $Id" -Sev 'Info'
                $Results.Add([pscustomobject]@{ Target = $Id; state = 'success'; resultText = "Deleted $($Set.Noun) $Id" })
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to delete $($Set.Noun) $Id`: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
                $Results.Add([pscustomobject]@{ Target = $Id; state = 'error'; resultText = "Failed to delete $($Set.Noun) $Id`: $($ErrorMessage.NormalizedError)" })
            }
        }
    }
    return $Results.ToArray()
}
