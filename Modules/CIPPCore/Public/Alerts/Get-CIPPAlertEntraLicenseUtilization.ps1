function Get-CIPPAlertEntraLicenseUtilization {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )
    try {
        # Set threshold with fallback to 110%
        $Threshold = if ($InputValue) { [int]$InputValue } else { 110 }

        $LicenseData = New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/reports/azureADPremiumLicenseInsight' -tenantid $($TenantFilter)
        $Alerts = [System.Collections.Generic.List[string]]::new()

        # Check P1 License utilization
        if ($LicenseData.entitledP1LicenseCount -gt 0) {
            $P1Used = $LicenseData.p1FeatureUtilizations.conditionalAccess.userCount
            $P1Entitled = $LicenseData.entitledP1LicenseCount
            $P1Usage = ($P1Used / $P1Entitled) * 100
            $P1Overage = $P1Used - $P1Entitled

            if ($P1Usage -gt $Threshold -and $P1Overage -ge 5) {
                $Alerts.Add("P1 License utilization is at $([math]::Round($P1Usage,2))% (Using $P1Used of $P1Entitled licenses, over by $P1Overage)")
            }
        }

        # Check P2 License utilization
        if ($LicenseData.entitledP2LicenseCount -gt 0) {
            $P2Used = $LicenseData.p2FeatureUtilizations.riskBasedConditionalAccess.userCount
            $P2Entitled = $LicenseData.entitledP2LicenseCount
            $P2Usage = ($P2Used / $P2Entitled) * 100
            $P2Overage = $P2Used - $P2Entitled

            if ($P2Usage -gt $Threshold -and $P2Overage -ge 5) {
                $Alerts.Add("P2 License utilization is at $([math]::Round($P2Usage,2))% (Using $P2Used of $P2Entitled licenses, over by $P2Overage)")
            }
        }

        if ($Alerts.Count -gt 0) {
            $AlertData = "License Over-utilization Alert (Threshold: $Threshold%, Min Overage: 5): $($Alerts -join ' | ')"
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -message "Failed to check license utilization: $($ErrorMessage.NormalizedError)" -API 'License Utilization Alert' -tenant $TenantFilter -sev Info -LogData $ErrorMessage
    }
}
