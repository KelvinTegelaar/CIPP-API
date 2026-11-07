function Invoke-CippTestZTNA24546 {
    <#
    .SYNOPSIS
    Windows automatic device enrollment is enforced to eliminate risks from unmanaged endpoints
    #>
    param($Tenant)

    $TestId = 'ZTNA24546'
    $Name = 'Windows automatic device enrollment is enforced to eliminate risks from unmanaged endpoints'

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset Entra -SkipLog)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Entra ID P1. Required capabilities: AAD_PREMIUM, AAD_PREMIUM_P2.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant'
            return
        }

        $MdmPolicies = Get-CIPPTestData -TenantFilter $Tenant -Type 'MobileDeviceManagementPolicies'
        if (-not $MdmPolicies) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant'
            return
        }

        $IntunePolicy = $MdmPolicies.Where({ $_.displayName -eq 'Microsoft Intune' }, 'First')[0]
        $Passed = [bool]($IntunePolicy -and $IntunePolicy.appliesTo -ne 'none')

        $ResultMarkdown = [System.Text.StringBuilder]::new($(if ($Passed) { "Windows Automatic Enrollment is enabled.`n`n" } else { "Windows Automatic Enrollment is not enabled.`n`n" }))
        if ($IntunePolicy) {
            $UserScope = switch ($IntunePolicy.appliesTo) {
                'none' { '❌ None' }
                'selected' { '✅ Specific Groups' }
                'all' { '✅ All Users' }
                default { '⚠️ Unknown Scope' }
            }
            $null = $ResultMarkdown.Append("## Windows Automatic Enrollment`n`n| Policy Name | User Scope |`n| :---------- | :--------- |`n")
            $null = $ResultMarkdown.Append("| [$($IntunePolicy.displayName)](https://intune.microsoft.com/#view/Microsoft_AAD_IAM/MdmConfiguration.ReactView/appId/0000000a-0000-0000-c000-000000000000/appName/Microsoft%20Intune) | $UserScope |`n")
        }

        $Status = if ($Passed) { 'Passed' } else { 'Failed' }
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown "$ResultMarkdown" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant'
    }
}
