function Invoke-CIPPBaselineEnableAppConsentRequests {
    <#
    .SYNOPSIS
        EnableAppConsentRequests executor: enables the admin consent workflow with the
        configured reviewer roles.
    .DESCRIPTION
        Read-merge-write, ported whole from the classic: the policy is fetched LIVE, flipped
        on with the fixed notification settings, and the configured roles become
        role-assignment reviewer queries MERGED into the existing reviewer list - reviewers
        an operator added by hand survive. The write is a full PUT because the policy does
        not support PATCH.

        No role configured defaults to Global Administrator, matching the hook's grade.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Policy = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/adminConsentRequestPolicy' -tenantid $TenantFilter
    if (-not $Policy) { throw 'Could not read the admin consent request policy - refusing a blind write.' }

    $Roles = @(@($Remediate.reviewerRoles) | ForEach-Object { "$($_.value ?? $_)" } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($Roles.Count -eq 0) { $Roles = @('62e90394-69f5-4237-9190-012177145e10') }

    $Policy.isEnabled = $true
    $Policy.notifyReviewers = $true
    $Policy.remindersEnabled = $true
    $Policy.requestDurationInDays = 30

    $Reviewers = [System.Collections.Generic.List[object]]::new()
    foreach ($Reviewer in @($Policy.reviewers)) {
        $RoleFound = $false
        foreach ($Role in $Roles) {
            if ("$($Reviewer.query)" -match $Role) { $RoleFound = $true }
        }
        if (-not $RoleFound) { $Reviewers.Add($Reviewer) }
    }
    foreach ($Role in $Roles) {
        $Reviewers.Add(@{
                query     = "/beta/roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '$Role'"
                queryType = 'MicrosoftGraph'
                queryRoot = 'null'
            })
    }
    $Policy.reviewers = @($Reviewers)

    $null = New-GraphPostRequest -tenantid $TenantFilter -uri 'https://graph.microsoft.com/beta/policies/adminConsentRequestPolicy' -type PUT -body (ConvertTo-Json -Compress -Depth 10 -InputObject $Policy)
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Enabled app consent requests with $($Roles.Count) reviewer role(s)." -Sev 'Info'
}
