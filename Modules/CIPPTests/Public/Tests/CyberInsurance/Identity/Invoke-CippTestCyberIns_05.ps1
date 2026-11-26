function Invoke-CippTestCyberIns_05 {
    <#
    .SYNOPSIS
    Cyber Insurance Q5 - MFA for backup systems
    #>
    param($Tenant)

    $Meta = @{ TenantFilter = $Tenant; TestId = 'CyberIns_05'; TestType = 'Identity'; Risk = 'High'; Name = 'MFA for backup systems'; UserImpact = 'Low'; ImplementationEffort = 'Medium'; Category = 'Cyber Insurance' }

    try {
        $Apps = Get-CIPPTestData -TenantFilter $Tenant -Type 'ServicePrincipals'
        if (-not $Apps) {
            Add-CippTestResult @Meta -Status 'Skipped' -ResultMarkdown 'No enterprise application data found for this tenant. Sync the report data first.'
            return
        }

        $BackupApps = [System.Collections.Generic.List[string]]::new()
        foreach ($App in $Apps) {
            if ($App.accountEnabled -eq $true -and $App.displayName -match 'backup|veeam|dropsuite|cove data|datto|acronis|axcient|druva|keepit|skykick|afi\.ai') {
                $BackupApps.Add([string]$App.displayName)
            }
        }

        $Result = [System.Text.StringBuilder]::new("A backup portal is only visible here when it signs in through Entra ID. This question needs an MSP attestation naming the backup product and its MFA method.`n`n")
        if ($BackupApps.Count -gt 0) {
            $null = $Result.Append("Enterprise apps that look like backup products, matched on name. These sign in through Entra ID, so the tenant's MFA policies apply to them:`n`n")
            foreach ($Name in $BackupApps) { $null = $Result.Append("- $Name`n") }
        } else {
            $null = $Result.Append('No enterprise app with a backup product name was found in this tenant.')
        }

        Add-CippTestResult @Meta -Status 'Informational' -ResultMarkdown $Result.ToString()
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CyberIns_05: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @Meta -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
