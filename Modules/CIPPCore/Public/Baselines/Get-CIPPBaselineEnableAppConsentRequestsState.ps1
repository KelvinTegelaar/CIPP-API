function Get-CIPPBaselineEnableAppConsentRequestsState {
    <#
    .SYNOPSIS
        Prepare hook for EnableAppConsentRequests: is the admin consent workflow on with the
        configured reviewers.
    .DESCRIPTION
        Grades the policy enabled flag and whether each configured role is PRESENT among
        the reviewers. The classic graded the reviewer COUNT, which never converges: a
        reviewer an operator added by hand bumps the count, and the remediation merge
        deliberately preserves that reviewer - so count-graded drift was permanent.
        Containment is what the merge write actually guarantees, the same reasoning that
        keeps QuarantineRequestAlert on a contains grade.

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

    @{
        Expected = [PSCustomObject]@{ appConsentRequestsEnabled = $true; missingReviewerRoles = @() }
        Current  = [PSCustomObject]@{
            appConsentRequestsEnabled = [bool]$Policy.isEnabled
            missingReviewerRoles      = @($MissingRoles)
        }
    }
}
