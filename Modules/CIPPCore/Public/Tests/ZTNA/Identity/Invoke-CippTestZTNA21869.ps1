function Invoke-CippTestZTNA21869 {
    <#
    .SYNOPSIS
    Enterprise applications must require explicit assignment or scoped provisioning
    #>
    param($Tenant)
    #tenant
    try {
        $ServicePrincipals = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ServicePrincipals'
        if (-not $ServicePrincipals) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21869' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Enterprise applications must require explicit assignment or scoped provisioning' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Application management'
            return
        }

        $AppsWithoutAssignment = $ServicePrincipals | Where-Object {
            $_.appRoleAssignmentRequired -eq $false -and
            $null -ne $_.preferredSingleSignOnMode -and
            $_.preferredSingleSignOnMode -in @('password', 'saml', 'oidc') -and
            $_.accountEnabled -eq $true
        }

        if (-not $AppsWithoutAssignment) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21869' -TestType 'Identity' -Status 'Passed' -ResultMarkdown 'All enterprise applications have explicit assignment requirements' -Risk 'Medium' -Name 'Enterprise applications must require explicit assignment or scoped provisioning' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Application management'
            return
        }

        $Status = 'Investigate'

        $ResultLines = @(
            "Found $($AppsWithoutAssignment.Count) enterprise application(s) without assignment requirements."
            ''
            '**Applications without user assignment requirements:**'
        )

        $Top10Apps = $AppsWithoutAssignment | Select-Object -First 10
        foreach ($App in $Top10Apps) {
            $ResultLines += "- $($App.displayName) (SSO: $($App.preferredSingleSignOnMode))"
        }

        if ($AppsWithoutAssignment.Count -gt 10) {
            $ResultLines += "- ... and $($AppsWithoutAssignment.Count - 10) more application(s)"
        }

        $ResultLines += ''
        $ResultLines += '**Note:** Full provisioning scope validation requires Graph API synchronization endpoint not available in cache.'
        $ResultLines += ''
        $ResultLines += '**Recommendation:** Enable user assignment requirements or configure scoped provisioning to limit application access.'

        $Result = $ResultLines -join "`n"

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21869' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Enterprise applications must require explicit assignment or scoped provisioning' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Application management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21869' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Enterprise applications must require explicit assignment or scoped provisioning' -UserImpact 'Medium' -ImplementationEffort 'Medium' -Category 'Application management'
    }
}
