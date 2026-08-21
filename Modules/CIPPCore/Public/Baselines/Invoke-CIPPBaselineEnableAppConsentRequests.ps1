function Invoke-CIPPBaselineEnableAppConsentRequests {
    <#
    .SYNOPSIS
        EnableAppConsentRequests executor: enables the admin consent workflow with the
        configured reviewer roles and users.
    .DESCRIPTION
        Read-merge-write, ported whole from the classic: the policy is fetched LIVE, flipped
        on with the fixed notification settings, and the configured roles become
        role-assignment reviewer queries MERGED into the existing reviewer list - reviewers
        an operator added by hand survive. The write is a full PUT because the policy does
        not support PATCH.

        Reviewer users are configured as display names and resolved to ids LIVE - display
        name rather than mail, because a guest's mail can land in mail, otherMails or
        nowhere depending on how the account was created, while the display name is
        whatever the operator typed regardless of creation path. A name that resolves to
        nothing is logged and skipped so the roles still land.

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

    $UserNames = @(@($Remediate.reviewerUsers) | ForEach-Object { "$($_.value ?? $_)" } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $Users = [System.Collections.Generic.List[object]]::new()
    foreach ($Name in $UserNames) {
        $UserFilter = [System.Uri]::EscapeDataString("displayName eq '$($Name -replace "'", "''")'")
        $Matched = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$select=id,displayName&`$filter=$UserFilter" -tenantid $TenantFilter)
        if ($Matched.Count -eq 0) {
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "EnableAppConsentRequests: no user found with display name '$Name' - not added as reviewer." -Sev 'Warning'
            continue
        }
        foreach ($User in $Matched) { $Users.Add($User) }
    }

    $Policy.isEnabled = $true
    $Policy.notifyReviewers = $true
    $Policy.remindersEnabled = $true
    $Policy.requestDurationInDays = 30

    $ManagedIds = @($Roles) + @($Users | ForEach-Object { "$($_.id)" })
    $Reviewers = [System.Collections.Generic.List[object]]::new()
    foreach ($Reviewer in @($Policy.reviewers)) {
        $Found = $false
        foreach ($Id in $ManagedIds) {
            if ("$($Reviewer.query)" -match $Id) { $Found = $true }
        }
        if (-not $Found) { $Reviewers.Add($Reviewer) }
    }
    foreach ($Role in $Roles) {
        $Reviewers.Add(@{
                query     = "/beta/roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '$Role'"
                queryType = 'MicrosoftGraph'
                queryRoot = 'null'
            })
    }
    foreach ($User in $Users) {
        $Reviewers.Add(@{
                query     = "/users/$($User.id)"
                queryType = 'MicrosoftGraph'
                queryRoot = 'null'
            })
    }
    $Policy.reviewers = @($Reviewers)

    $null = New-GraphPostRequest -tenantid $TenantFilter -uri 'https://graph.microsoft.com/beta/policies/adminConsentRequestPolicy' -type PUT -body (ConvertTo-Json -Compress -Depth 10 -InputObject $Policy)
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Enabled app consent requests with $($Roles.Count) reviewer role(s) and $($Users.Count) reviewer user(s)." -Sev 'Info'
}
