function Invoke-CippTestZTNA21772 {
    <#
    .SYNOPSIS
    Applications do not have client secrets configured
    #>
    param($Tenant)
    #tested
    try {
        $Apps = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Apps'
        $ServicePrincipals = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ServicePrincipals'

        if (-not $Apps -and -not $ServicePrincipals) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21772' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Applications do not have client secrets configured' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application Management'
            return
        }

        $AppsWithSecrets = @()
        $SPsWithSecrets = @()

        if ($Apps) {
            $AppsWithSecrets = $Apps | Where-Object {
                $_.passwordCredentials -and
                $_.passwordCredentials.Count -gt 0 -and
                $_.passwordCredentials -ne '[]'
            }
        }

        if ($ServicePrincipals) {
            $SPsWithSecrets = $ServicePrincipals | Where-Object {
                $_.passwordCredentials -and
                $_.passwordCredentials.Count -gt 0 -and
                $_.passwordCredentials -ne '[]'
            }
        }

        $TotalWithSecrets = $AppsWithSecrets.Count + $SPsWithSecrets.Count

        if ($TotalWithSecrets -eq 0) {
            $Status = 'Passed'
            $Result = 'Applications in your tenant do not use client secrets'
        } else {
            $Status = 'Failed'
            $Result = @"
Found $($AppsWithSecrets.Count) applications and $($SPsWithSecrets.Count) service principals with client secrets configured
## Apps with client secrets:
$(($AppsWithSecrets | ForEach-Object { "- $($_.displayName) (AppId: $($_.appId))" }) -join "`n")
## Service principals with client secrets:
$(($SPsWithSecrets | ForEach-Object { "- $($_.displayName) (AppId: $($_.appId))" }) -join "`n")
"@
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21772' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Applications do not have client secrets configured' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21772' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Applications do not have client secrets configured' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application Management'
    }
}
