function Get-CIPPBaselineEnableAppConsentRequestsState {
    <#
    .SYNOPSIS
        Prepare hook for EnableAppConsentRequests: is the admin consent workflow on with the
        configured reviewers.
    .DESCRIPTION
        Grades the policy enabled flag and whether each configured role and user is PRESENT
        among the reviewers. The classic graded the reviewer COUNT, which never converges: a
        reviewer an operator added by hand bumps the count, and the remediation merge
        deliberately preserves that reviewer - so count-graded drift was permanent.
        Containment is what the merge write actually guarantees, the same reasoning that
        keeps QuarantineRequestAlert on a contains grade.

        Reviewer users are configured as display names (not mail - a guest's mail attribute
        depends on how the account was created) and resolved against the Users cache, joined
        through Get-CIPPBaselineCacheRows because Users is not this definition's primary
        cache. A name that resolves to no cached user is graded missing: the account the
        operator expects to review requests does not exist in the tenant. Reviewer queries
        are matched on both id and UPN since hand-added user reviewers can carry either.

        No role configured defaults to Global Administrator, matching the classic in both
        the grade and the write.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Policy = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'AdminConsentRequestPolicy') | Select-Object -First 1
    if (-not $Policy) { return @{ Current = $null } }

    $Roles = @(@($Item.Variables.ReviewerRoles) | ForEach-Object { "$($_.value ?? $_)" } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($Roles.Count -eq 0) { $Roles = @('62e90394-69f5-4237-9190-012177145e10') }

    $ReviewerQueries = @(@($Policy.reviewers) | ForEach-Object { "$($_.query)" })
    $MissingRoles = @($Roles | Where-Object { $Role = $_; -not ($ReviewerQueries | Where-Object { $_ -match $Role }) })

    $UserNames = @(@($Item.Variables.ReviewerUsers) | ForEach-Object { "$($_.value ?? $_)" } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $MissingUsers = @()
    if ($UserNames.Count -gt 0) {
        $Users = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'Users')
        $MissingUsers = @($UserNames | Where-Object {
                $Name = $_
                $Covered = @($Users) | Where-Object { $_.displayName -eq $Name } | Where-Object {
                    $User = $_
                    $ReviewerQueries | Where-Object { $_ -match [regex]::Escape("$($User.id)") -or (-not [string]::IsNullOrWhiteSpace($User.userPrincipalName) -and $_ -match [regex]::Escape("$($User.userPrincipalName)")) }
                }
                -not $Covered
            })
    }

    @{
        Expected = [PSCustomObject]@{ appConsentRequestsEnabled = $true; missingReviewerRoles = @(); missingReviewerUsers = @() }
        Current  = [PSCustomObject]@{
            appConsentRequestsEnabled = [bool]$Policy.isEnabled
            missingReviewerRoles      = @($MissingRoles)
            missingReviewerUsers      = @($MissingUsers)
        }
    }
}
