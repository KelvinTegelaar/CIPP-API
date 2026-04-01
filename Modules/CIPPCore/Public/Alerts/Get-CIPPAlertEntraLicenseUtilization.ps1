function Get-CIPPAlertEntraLicenseUtilization {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )
    try {
        # Set threshold with fallback to 110%
        $Threshold = if ($InputValue) { [int]$InputValue } else { 110 }

        $LicenseData = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/reports/azureADPremiumLicenseInsight' -tenantid $($TenantFilter)

        $AlertData = @(
            # Check P1 License utilization
            if ($LicenseData.entitledP1LicenseCount -gt 0 -or $LicenseData.entitledP2LicenseCount -gt 0) {
                $P1Used = $LicenseData.p1FeatureUtilizations.conditionalAccess.userCount
                $P1Entitled = $LicenseData.entitledP1LicenseCount + $LicenseData.entitledP2LicenseCount
                $P1Usage = [math]::Round(($P1Used / $P1Entitled) * 100, 2)
                $P1Overage = $P1Used - $P1Entitled

                if ($P1Usage -gt $Threshold -and $P1Overage -ge 5) {
                    [PSCustomObject]@{
                        Message          = "Entra ID P1 license utilization is at $P1Usage% (using $P1Used of $P1Entitled licenses, over by $P1Overage)"
                        LicenseType      = 'Entra ID P1'
                        UsedLicenses     = $P1Used
                        EntitledLicenses = $P1Entitled
                        UsagePercent     = $P1Usage
                        Overage          = $P1Overage
                        Threshold        = $Threshold
                        Tenant           = $TenantFilter
                    }
                }
            }

            # Check P2 License utilization
            if ($LicenseData.entitledP2LicenseCount -gt 0) {
                $P2Used = $LicenseData.p2FeatureUtilizations.riskBasedConditionalAccess.userCount
                $P2Entitled = $LicenseData.entitledP2LicenseCount
                $P2Usage = [math]::Round(($P2Used / $P2Entitled) * 100, 2)
                $P2Overage = $P2Used - $P2Entitled

                if ($P2Usage -gt $Threshold -and $P2Overage -ge 5) {
                    [PSCustomObject]@{
                        Message          = "Entra ID P2 license utilization is at $P2Usage% (using $P2Used of $P2Entitled licenses, over by $P2Overage)"
                        LicenseType      = 'Entra ID P2'
                        UsedLicenses     = $P2Used
                        EntitledLicenses = $P2Entitled
                        UsagePercent     = $P2Usage
                        Overage          = $P2Overage
                        Threshold        = $Threshold
                        Tenant           = $TenantFilter
                    }
                }
            }
        )

        if ($AlertData.Count -gt 0) {
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -message "Failed to check license utilization: $($ErrorMessage.NormalizedError)" -API 'License Utilization Alert' -tenant $TenantFilter -sev Info -LogData $ErrorMessage
    }
}
