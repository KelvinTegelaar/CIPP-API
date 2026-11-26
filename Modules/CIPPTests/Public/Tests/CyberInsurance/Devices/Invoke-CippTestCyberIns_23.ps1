function Invoke-CippTestCyberIns_23 {
    <#
    .SYNOPSIS
    Cyber Insurance Q23 - Regular vulnerability scans are performed
    #>
    param($Tenant)

    $Meta = @{ TenantFilter = $Tenant; TestId = 'CyberIns_23'; TestType = 'Devices'; Risk = 'Medium'; Name = 'Regular vulnerability scans are performed'; UserImpact = 'Low'; ImplementationEffort = 'Medium'; Category = 'Cyber Insurance' }

    try {
        if (-not (Test-CIPPStandardLicense -StandardName 'CyberIns_23' -TenantFilter $Tenant -Preset DefenderVulnerabilityManagement -SkipLog)) {
            Add-CippTestResult @Meta -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Defender Vulnerability Management. Vulnerability scanning needs an MSP attestation.'
            return
        }

        $Machines = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'DefenderMachines').Where({ $_.onboardingStatus -eq 'Onboarded' }).Count
        $Severity = @{}
        $Total = 0
        foreach ($Cve in (Get-CIPPTestData -TenantFilter $Tenant -Type 'DefenderCVEs')) {
            $Total++
            $Level = if ($Cve.vulnerabilitySeverityLevel) { [string]$Cve.vulnerabilitySeverityLevel } else { 'Unknown' }
            $Severity[$Level] = [int]$Severity[$Level] + 1
        }

        if ($Machines -eq 0 -and $Total -eq 0) {
            Add-CippTestResult @Meta -Status 'Skipped' -ResultMarkdown 'Defender Vulnerability Management is licensed, but no devices or vulnerabilities were found. Devices may not be onboarded to Defender for Endpoint yet.'
            return
        }

        $Result = "Microsoft Defender Vulnerability Management scans **$Machines** onboarded devices continuously. It currently reports **$Total** vulnerabilities: $([int]$Severity['Critical']) critical, $([int]$Severity['High']) high, $([int]$Severity['Medium']) medium and $([int]$Severity['Low']) low.`n`nExternal and network vulnerability scanning is not visible here and needs an MSP attestation."

        Add-CippTestResult @Meta -Status 'Passed' -ResultMarkdown $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test CyberIns_23: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @Meta -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
