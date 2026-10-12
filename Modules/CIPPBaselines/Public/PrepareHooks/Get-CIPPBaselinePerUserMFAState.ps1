function Get-CIPPBaselinePerUserMFAState {
    <#
    .SYNOPSIS
        Prepare hook for PerUserMFA: enabled member accounts not on enforced per-user MFA.
    .DESCRIPTION
        The AD sync account is excluded by display name, exactly as the classic standard did:
        it cannot complete MFA and enforcing it breaks directory synchronisation.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Users = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Users' | Where-Object { $_ })
    if ($Users.Count -eq 0) { return @{ Current = $null } }

    $WithoutMFA = @($Users | Where-Object {
            $_.userType -eq 'Member' -and
            $_.accountEnabled -eq $true -and
            $_.displayName -ne 'On-Premises Directory Synchronization Service Account' -and
            $_.perUserMfaState -ne 'enforced'
        })

    @{
        Current = [PSCustomObject]@{
            offenders = @($WithoutMFA.userPrincipalName | Sort-Object)
            targets   = @($WithoutMFA | ForEach-Object { [PSCustomObject]@{ id = "$($_.userPrincipalName)" } })
        }
    }
}
