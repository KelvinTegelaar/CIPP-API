function Get-CIPPBaselineDisableExchangeOnlinePowerShellState {
    <#
    .SYNOPSIS
        Prepare hook for DisableExchangeOnlinePowerShell: non-admin mailboxes that still have
        Exchange Online PowerShell.
    .DESCRIPTION
        The offender set is the Mailboxes cache minus every admin, and the admin set is the
        part that cannot come from cache: directory role assignments, plus the TRANSITIVE
        members of any group holding a role. A group-derived admin is still an admin, and
        stripping their PowerShell access is exactly the outage this standard must not cause,
        so the expansion is read live like the classic standard did.

        If the admin lookup fails the hook returns a null Current rather than an offender set:
        an empty admin list would sweep every administrator in the tenant.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Mailboxes = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Mailboxes' | Where-Object { $_ })
    if ($Mailboxes.Count -eq 0) { return @{ Current = $null } }

    try {
        $RoleAssignments = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?$select=id,principalId,roleDefinitionId,directoryScopeId&$expand=principal($select=id,userPrincipalName)' -tenantid $TenantFilter
        $AdminUPNs = @(($RoleAssignments | Where-Object { $_.principal.'@odata.type' -eq '#microsoft.graph.user' }).principal.userPrincipalName)
        $AdminGroupIds = @(($RoleAssignments | Where-Object { $_.principal.'@odata.type' -eq '#microsoft.graph.group' }).principal.id | Select-Object -Unique)
        if ($AdminGroupIds.Count -gt 0) {
            $BulkRequests = foreach ($GroupId in $AdminGroupIds) {
                @{ id = $GroupId; method = 'GET'; url = "groups/$GroupId/transitiveMembers/microsoft.graph.user?`$select=userPrincipalName" }
            }
            $BulkResults = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($BulkRequests) -Version 'v1.0'
            $AdminUPNs += @($BulkResults.body.value.userPrincipalName)
        }
    } catch {
        Write-Information "Baselines: admin-role lookup on $TenantFilter failed, refusing to sweep: $($_.Exception.Message)"
        return @{ Current = $null }
    }

    $Admins = @{}
    foreach ($UPN in ($AdminUPNs | Where-Object { $_ })) { $Admins["$UPN"] = $true }

    $Offending = @($Mailboxes | Where-Object {
            $_.RemotePowerShellEnabled -eq $true -and -not $Admins.ContainsKey("$($_.UPN)")
        })

    @{
        Current = [PSCustomObject]@{
            offenders = @($Offending.UPN | Sort-Object)
            # Identity prefers the immutable Guid: a UPN can change between the read and the
            # write, and Set-User would then target nobody.
            targets   = @($Offending | ForEach-Object { [PSCustomObject]@{ id = "$($_.Guid ?? $_.UPN)" } })
        }
    }
}
