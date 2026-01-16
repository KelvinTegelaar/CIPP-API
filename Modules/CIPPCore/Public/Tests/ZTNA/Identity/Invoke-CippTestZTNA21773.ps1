function Invoke-CippTestZTNA21773 {
    <#
    .SYNOPSIS
    Applications do not have certificates with expiration longer than 180 days
    #>
    param($Tenant)
    #tested
    try {
        $Apps = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Apps'
        $ServicePrincipals = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ServicePrincipals'

        if (-not $Apps -and -not $ServicePrincipals) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21773' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Applications do not have certificates with expiration longer than 180 days' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application Management'
            return
        }

        $MaxDate = (Get-Date).AddDays(180)
        $AppsWithLongCerts = @()
        $SPsWithLongCerts = @()

        if ($Apps) {
            $AppsWithLongCerts = $Apps | Where-Object {
                if ($_.keyCredentials -and $_.keyCredentials.Count -gt 0 -and $_.keyCredentials -ne '[]') {
                    $HasLongCert = $false
                    foreach ($Cred in $_.keyCredentials) {
                        if ($Cred.endDateTime) {
                            $EndDate = [datetime]$Cred.endDateTime
                            if ($EndDate -gt $MaxDate) {
                                $HasLongCert = $true
                                break
                            }
                        }
                    }
                    $HasLongCert
                } else {
                    $false
                }
            }
        }

        if ($ServicePrincipals) {
            $SPsWithLongCerts = $ServicePrincipals | Where-Object {
                if ($_.keyCredentials -and $_.keyCredentials.Count -gt 0 -and $_.keyCredentials -ne '[]') {
                    $HasLongCert = $false
                    foreach ($Cred in $_.keyCredentials) {
                        if ($Cred.endDateTime) {
                            $EndDate = [datetime]$Cred.endDateTime
                            if ($EndDate -gt $MaxDate) {
                                $HasLongCert = $true
                                break
                            }
                        }
                    }
                    $HasLongCert
                } else {
                    $false
                }
            }
        }

        $TotalWithLongCerts = $AppsWithLongCerts.Count + $SPsWithLongCerts.Count

        if ($TotalWithLongCerts -eq 0) {
            $Status = 'Passed'
            $Result = 'Applications in your tenant do not have certificates valid for more than 180 days'
        } else {
            $Status = 'Failed'
            $Result = "Found $($AppsWithLongCerts.Count) applications and $($SPsWithLongCerts.Count) service principals with certificates longer than 180 days`n`n"

            if ($AppsWithLongCerts.Count -gt 0) {
                $Result += "## Apps with long-lived certificates:`n`n"
                $Result += ($AppsWithLongCerts | ForEach-Object { "- $($_.displayName) (AppId: $($_.appId))" }) -join "`n"
                $Result += "`n`n"
            }

            if ($SPsWithLongCerts.Count -gt 0) {
                $Result += "## Service principals with long-lived certificates:`n`n"
                $Result += ($SPsWithLongCerts | ForEach-Object { "- $($_.displayName) (AppId: $($_.appId))" }) -join "`n"
            }
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21773' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name 'Applications do not have certificates with expiration longer than 180 days' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application Management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21773' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Applications do not have certificates with expiration longer than 180 days' -UserImpact 'Low' -ImplementationEffort 'Medium' -Category 'Application Management'
    }
}
