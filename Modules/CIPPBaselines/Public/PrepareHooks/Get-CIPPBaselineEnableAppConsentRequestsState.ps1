function Get-CIPPBaselineEnableAppConsentRequestsState {
    <#
    .SYNOPSIS
        Prepare hook for EnableAppConsentRequests: is the admin consent workflow on with the
        configured reviewers.
    .DESCRIPTION
        Grades the policy enabled flag and whether each configured role, user and group is
        PRESENT among the reviewers. The classic graded the reviewer COUNT, which never converges: a
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

        Reviewer groups are likewise configured as display names (one shared "consent
        reviewers" group created in every tenant has a different id per tenant) and resolved
        against the Groups cache. The admin center's Groups option writes the reviewer as the
        group's transitive user members (/v1.0/groups/{id}/transitiveMembers/microsoft.graph.user),
        so a group is graded present when any reviewer query carries its id.

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

    # Missing roles are reported by name (the classic standard does the same), falling back to the id
    $RoleLabels = @{ '62e90394-69f5-4237-9190-012177145e10' = 'Global Administrator' }
    foreach ($Role in @($Item.Variables.ReviewerRoles)) { if ($Role.value) { $RoleLabels["$($Role.value)"] = $Role.label ?? $Role.value } }

    $ReviewerQueries = @(@($Policy.reviewers) | ForEach-Object { "$($_.query)" })
    $MissingRoles = @($Roles | Where-Object { $Role = $_; -not ($ReviewerQueries | Where-Object { $_ -match [regex]::Escape($Role) }) } | ForEach-Object { $RoleLabels[$_] ?? $_ })

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

    $GroupNames = @(@($Item.Variables.ReviewerGroups) | ForEach-Object { "$($_.value ?? $_)" } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $MissingGroups = @()
    if ($GroupNames.Count -gt 0) {
        $Groups = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'Groups')
        $MissingGroups = @($GroupNames | Where-Object {
                $Name = $_
                $Covered = @($Groups) | Where-Object { $_.displayName -eq $Name } | Where-Object {
                    $Group = $_
                    $ReviewerQueries | Where-Object { $_ -match [regex]::Escape("$($Group.id)") }
                }
                -not $Covered
            })
    }

    @{
        Expected = [PSCustomObject]@{ appConsentRequestsEnabled = $true; missingReviewerRoles = @(); missingReviewerUsers = @(); missingReviewerGroups = @() }
        Current  = [PSCustomObject]@{
            appConsentRequestsEnabled = [bool]$Policy.isEnabled
            missingReviewerRoles      = @($MissingRoles)
            missingReviewerUsers      = @($MissingUsers)
            missingReviewerGroups     = @($MissingGroups)
        }
    }
}
