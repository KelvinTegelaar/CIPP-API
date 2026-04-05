function Invoke-CippTestZTNA21992 {
    <#
    .SYNOPSIS
    Application certificates must be rotated on a regular basis
    #>
    param($Tenant)

    try {
        $Apps = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Apps'
        $ServicePrincipals = New-CIPPDbRequest -TenantFilter $Tenant -Type 'ServicePrincipals'
        #Tested
        if (-not $Apps -and -not $ServicePrincipals) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21992' -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Application certificates must be rotated on a regular basis' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Application management'
            return
        }

        $RotationThresholdDays = 180
        $ThresholdDate = (Get-Date).AddDays(-$RotationThresholdDays)

        $OldAppCerts = @()
        if ($Apps) {
            $OldAppCerts = $Apps | Where-Object {
                $_.keyCredentials -and $_.keyCredentials.Count -gt 0
            } | ForEach-Object {
                $App = $_
                $OldestCert = $App.keyCredentials | Where-Object { $_.startDateTime } | ForEach-Object {
                    [DateTime]$_.startDateTime
                } | Sort-Object | Select-Object -First 1

                if ($OldestCert -and $OldestCert -lt $ThresholdDate) {
                    [PSCustomObject]@{
                        Type           = 'Application'
                        DisplayName    = $App.displayName
                        AppId          = $App.appId
                        Id             = $App.id
                        OldestCertDate = $OldestCert
                    }
                }
            }
        }

        $OldSPCerts = @()
        if ($ServicePrincipals) {
            $OldSPCerts = $ServicePrincipals | Where-Object {
                $_.keyCredentials -and $_.keyCredentials.Count -gt 0
            } | ForEach-Object {
                $SP = $_
                $OldestCert = $SP.keyCredentials | Where-Object { $_.startDateTime } | ForEach-Object {
                    [DateTime]$_.startDateTime
                } | Sort-Object | Select-Object -First 1

                if ($OldestCert -and $OldestCert -lt $ThresholdDate) {
                    [PSCustomObject]@{
                        Type           = 'ServicePrincipal'
                        DisplayName    = $SP.displayName
                        AppId          = $SP.appId
                        Id             = $SP.id
                        OldestCertDate = $OldestCert
                    }
                }
            }
        }

        if ($OldAppCerts.Count -eq 0 -and $OldSPCerts.Count -eq 0) {
            Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21992' -TestType 'Identity' -Status 'Passed' -ResultMarkdown "Certificates for applications in your tenant have been issued within $RotationThresholdDays days" -Risk 'High' -Name 'Application certificates must be rotated on a regular basis' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Application management'
            return
        }

        $Status = 'Failed'

        $ResultLines = @(
            "Found $($OldAppCerts.Count) application(s) and $($OldSPCerts.Count) service principal(s) with certificates not rotated within $RotationThresholdDays days."
            ''
            "**Certificate rotation threshold:** $RotationThresholdDays days"
            ''
        )

        if ($OldAppCerts.Count -gt 0) {
            $ResultLines += '**Applications with old certificates:**'
            $Top10Apps = $OldAppCerts | Select-Object -First 10
            foreach ($App in $Top10Apps) {
                $DaysOld = [Math]::Round(((Get-Date) - $App.OldestCertDate).TotalDays, 0)
                $ResultLines += "- $($App.DisplayName) (Certificate age: $DaysOld days)"
            }
            if ($OldAppCerts.Count -gt 10) {
                $ResultLines += "- ... and $($OldAppCerts.Count - 10) more application(s)"
            }
            $ResultLines += ''
        }

        if ($OldSPCerts.Count -gt 0) {
            $ResultLines += '**Service principals with old certificates:**'
            $Top10SPs = $OldSPCerts | Select-Object -First 10
            foreach ($SP in $Top10SPs) {
                $DaysOld = [Math]::Round(((Get-Date) - $SP.OldestCertDate).TotalDays, 0)
                $ResultLines += "- $($SP.DisplayName) (Certificate age: $DaysOld days)"
            }
            if ($OldSPCerts.Count -gt 10) {
                $ResultLines += "- ... and $($OldSPCerts.Count - 10) more service principal(s)"
            }
            $ResultLines += ''
        }

        $ResultLines += '**Recommendation:** Rotate certificates regularly to reduce the risk of credential compromise.'

        $Result = $ResultLines -join "`n"

        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21992' -TestType 'Identity' -Status $Status -ResultMarkdown $Result -Risk 'High' -Name 'Application certificates must be rotated on a regular basis' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Application management'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId 'ZTNA21992' -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Application certificates must be rotated on a regular basis' -UserImpact 'Low' -ImplementationEffort 'High' -Category 'Application management'
    }
}
