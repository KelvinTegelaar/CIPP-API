function Invoke-CippTestZTNA24871 {
    <#
    .SYNOPSIS
    Defender for Endpoint automatic enrollment is enforced to reduce risk from unmanaged Android threats
    #>
    param($Tenant)

    $TestId = 'ZTNA24871'
    $Name = 'Defender for Endpoint automatic enrollment is enforced to reduce risk from unmanaged Android threats'

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset Intune -SkipLog)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Intune.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant'
            return
        }

        $Connectors = Get-CIPPTestData -TenantFilter $Tenant -Type 'MDEOnboarding'
        if (-not $Connectors) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant'
            return
        }

        # The collector stores a stub without an id when the connector does not exist
        $Defender = $Connectors.Where({ $_.id -eq 'fc780465-2017-40d4-a0c5-307022471b92' }, 'First')[0]

        if ($Defender) {
            $Passed = $Defender.partnerState -eq 'enabled' -and $Defender.androidEnabled -eq $true
            $Summary = if ($Passed) { 'Mobile Threat Defense Connector is enabled and Android enrollment is active.' } else { 'Mobile Threat Defense Connector is disabled or Android enrollment is not enabled.' }
            $State = if ($Defender.partnerState) { (Get-Culture).TextInfo.ToTitleCase(([string]$Defender.partnerState).ToLower()) } else { 'Unknown' }
            $ResultMarkdown = "$Summary`n`n## [Microsoft Defender for Endpoint Enrollment for Android Devices](https://intune.microsoft.com/#view/Microsoft_Intune_Workflows/SecurityManagementMenu/~/atp)`n`n| Status | Android Enrollment |`n| :----- | :----------------- |`n| $State | $([bool]$Defender.androidEnabled) |`n"
        } else {
            $Passed = $false
            $ResultMarkdown = 'No Microsoft Defender for Endpoint Connector found in the tenant.'
        }

        $Status = if ($Passed) { 'Passed' } else { 'Failed' }
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown $ResultMarkdown -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant'
    }
}
