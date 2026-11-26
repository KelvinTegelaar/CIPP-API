function Invoke-CippTestCyberIns_02 {
    <#
    .SYNOPSIS
    Cyber Insurance Q2 - MFA for remote network access (VPN, RDP)
    #>
    param($Tenant)

    $Meta = @{ TenantFilter = $Tenant; TestId = 'CyberIns_02'; TestType = 'Identity'; Risk = 'High'; Name = 'MFA for remote network access (VPN, RDP)'; UserImpact = 'Medium'; ImplementationEffort = 'Medium'; Category = 'Cyber Insurance' }

    try {
        $Policies = Get-CIPPTestData -TenantFilter $Tenant -Type 'ConditionalAccessPolicies'
        $AllApps = 0
        $SpecificApps = [System.Collections.Generic.List[string]]::new()
        foreach ($Policy in $Policies) {
            if ($Policy.state -ne 'enabled') { continue }
            if ($Policy.grantControls.builtInControls -notcontains 'mfa' -and -not $Policy.grantControls.authenticationStrength) { continue }
            if ($Policy.conditions.applications.includeApplications -contains 'All') { $AllApps++ } else { $SpecificApps.Add([string]$Policy.displayName) }
        }

        $Result = [System.Text.StringBuilder]::new("VPN and RDP sign-ins are only visible here when they sign in through Entra ID. This question needs an MSP attestation naming the remote access tool and its MFA method.`n`n")
        $null = $Result.Append("Supporting evidence from the tenant: **$AllApps** enabled Conditional Access policies require MFA for all cloud apps, and **$($SpecificApps.Count)** require MFA for specific apps.`n")
        if ($SpecificApps.Count -gt 0) {
            $null = $Result.Append("`nPolicies requiring MFA for specific apps:`n`n")
            foreach ($Name in $SpecificApps) { $null = $Result.Append("- $Name`n") }
        }

        Add-CippTestResult @Meta -Status 'Informational' -ResultMarkdown $Result.ToString()
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CyberIns_02: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @Meta -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
