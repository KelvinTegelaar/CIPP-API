function Get-CIPPBaselineUserPreferredLanguageState {
    <#
    .SYNOPSIS
        Prepare hook for UserPreferredLanguage: users whose preferred language is not the
        configured one.
    .DESCRIPTION
        Members only, and never a directory-synced account - the language is mastered on
        premises for those and Graph rejects the write.
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

    $Wanted = "$($Item.Variables.preferredLanguage)"
    $Incorrect = @($Users | Where-Object {
            $_.userType -eq 'Member' -and
            $_.onPremisesSyncEnabled -ne $true -and
            "$($_.preferredLanguage)" -ne $Wanted
        })

    @{
        Current = [PSCustomObject]@{
            offenders = @($Incorrect.userPrincipalName | Sort-Object)
            targets   = @($Incorrect | ForEach-Object { [PSCustomObject]@{ id = "$($_.userPrincipalName)" } })
        }
    }
}
