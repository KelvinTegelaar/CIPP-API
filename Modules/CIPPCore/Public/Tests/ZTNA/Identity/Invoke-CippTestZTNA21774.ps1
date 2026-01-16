function Invoke-CippTestZTNA21774 {
    <#
    .SYNOPSIS
    Microsoft services applications do not have credentials configured
    #>
    param($Tenant)

    try {
        $ServicePrincipals = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ServicePrincipals'
        #tested
        if (-not $ServicePrincipals) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21774' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Microsoft services applications do not have credentials configured' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Application Management'
            return
        }

        $MicrosoftTenantId = 'f8cdef31-a31e-4b4a-93e4-5f571e91255a'

        $MicrosoftSPs = $ServicePrincipals | Where-Object {
            $_.appOwnerOrganizationId -eq $MicrosoftTenantId
        }

        $SPsWithPasswordCreds = @()
        $SPsWithKeyCreds = @()

        if ($MicrosoftSPs) {
            $SPsWithPasswordCreds = $MicrosoftSPs | Where-Object {
                $_.passwordCredentials -and
                $_.passwordCredentials.Count -gt 0 -and
                $_.passwordCredentials -ne '[]'
            }

            $SPsWithKeyCreds = $MicrosoftSPs | Where-Object {
                $_.keyCredentials -and
                $_.keyCredentials.Count -gt 0 -and
                $_.keyCredentials -ne '[]'
            }
        }

        $TotalWithCreds = $SPsWithPasswordCreds.Count + $SPsWithKeyCreds.Count

        if ($TotalWithCreds -eq 0) {
            $Status = 'Passed'
            $Result = 'No Microsoft services applications have credentials configured in the tenant'
        } else {
            $Status = 'Investigate'
            $Result = @"
Found Microsoft services applications with credentials configured: $($SPsWithPasswordCreds.Count) with password credentials, $($SPsWithKeyCreds.Count) with key credentials
## Service principals with password credentials:
$(($SPsWithPasswordCreds | ForEach-Object { "- $($_.displayName) (AppId: $($_.appId))" }) -join "`n")
## Service principals with key credentials:
$(($SPsWithKeyCreds | ForEach-Object { "- $($_.displayName) (AppId: $($_.appId))" }) -join "`n")
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21774' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Microsoft services applications do not have credentials configured' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Application Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21774' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Microsoft services applications do not have credentials configured' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Application Management'
    }
}
