function Invoke-CippTestZTNA21896 {
    <#
    .SYNOPSIS
    Service principals do not have certificates or credentials associated with them
    #>
    param($Tenant)
    #tested
    try {
        $ServicePrincipals = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ServicePrincipals'
        if (-not $ServicePrincipals) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21896' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Service principals do not have certificates or credentials associated with them' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application management'
            return
        }

        $MicrosoftOwnerId = 'f8cdef31-a31e-4b4a-93e4-5f571e91255a'
        $SPsWithPassCreds = $ServicePrincipals | Where-Object {
            $_.passwordCredentials -and $_.passwordCredentials.Count -gt 0 -and $_.appOwnerOrganizationId -ne $MicrosoftOwnerId
        }
        $SPsWithKeyCreds = $ServicePrincipals | Where-Object {
            $_.keyCredentials -and $_.keyCredentials.Count -gt 0 -and $_.appOwnerOrganizationId -ne $MicrosoftOwnerId
        }

        if (-not $SPsWithPassCreds -and -not $SPsWithKeyCreds) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21896' -TestType 'Identity' -Status 'Passed' -ResultMarkdown 'Service principals do not have credentials associated with them' -Risk 'Medium' -Name 'Service principals do not have certificates or credentials associated with them' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application management'
            return
        }

        $TotalWithCreds = $SPsWithPassCreds.Count + $SPsWithKeyCreds.Count
        $Status = 'Investigate'

        $ResultLines = @(
            "Found $TotalWithCreds service principal(s) with credentials configured in the tenant, which represents a security risk."
            ''
        )

        if ($SPsWithPassCreds.Count -gt 0) {
            $ResultLines += "**Service principals with password credentials:** $($SPsWithPassCreds.Count)"
            $ResultLines += ''
        }

        if ($SPsWithKeyCreds.Count -gt 0) {
            $ResultLines += "**Service principals with key credentials (certificates):** $($SPsWithKeyCreds.Count)"
            $ResultLines += ''
        }

        $ResultLines += '**Security implications:**'
        $ResultLines += '- Service principals with credentials can be compromised if not properly secured'
        $ResultLines += '- Password credentials are less secure than managed identities or certificate-based authentication'
        $ResultLines += '- Consider using managed identities where possible to eliminate credential management'

        $Result = $ResultLines -join "`n"

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21896' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Service principals do not have certificates or credentials associated with them' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21896' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Service principals do not have certificates or credentials associated with them' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application management'
    }
}
