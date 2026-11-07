function Invoke-CippTestZTNA24823 {
    <#
    .SYNOPSIS
    Company Portal branding and support settings enhance user experience and trust
    #>
    param($Tenant)

    $TestId = 'ZTNA24823'
    $Name = 'Company Portal branding and support settings enhance user experience and trust'

    try {
        if (-not (Test-CIPPStandardLicense -StandardName $TestId -TenantFilter $Tenant -Preset Intune -SkipLog)) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Intune.' -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant'
            return
        }

        $Profiles = Get-CIPPTestData -TenantFilter $Tenant -Type 'IntuneBrandingProfile'
        if (-not $Profiles) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant'
            return
        }

        $CompleteProfiles = $Profiles.Where({ $_.displayName -and $_.contactITPhoneNumber -and $_.contactITEmailAddress })
        $CompleteCustomProfiles = $CompleteProfiles.Where({ $_.isDefaultProfile -ne $true })

        # Profile assignments are not cached, so a complete custom profile cannot be confirmed as assigned
        if ($CompleteProfiles.Where({ $_.isDefaultProfile -eq $true }).Count -gt 0) {
            $Status = 'Passed'
            $Summary = 'The default Company Portal branding profile has the required display name and IT contact details.'
        } elseif ($CompleteCustomProfiles.Count -gt 0) {
            $Status = 'Investigate'
            $Summary = 'The default Company Portal branding profile is missing required properties. A custom branding profile has them; confirm it is assigned to users.'
        } else {
            $Status = 'Failed'
            $Summary = 'No Company Portal branding profile with support settings exists.'
        }

        $ResultMarkdown = [System.Text.StringBuilder]::new("$Summary`n`n## Company Portal Branding Profiles`n`n| Profile Name | Default | Display Name | Contact Phone | Contact Email |`n| :----------- | :------ | :----------- | :------------ | :------------ |`n")
        foreach ($BrandingProfile in $Profiles) {
            $Default = if ($BrandingProfile.isDefaultProfile -eq $true) { 'Yes' } else { 'No' }
            $DisplayName = if ($BrandingProfile.displayName) { $BrandingProfile.displayName } else { 'Not configured' }
            $Phone = if ($BrandingProfile.contactITPhoneNumber) { $BrandingProfile.contactITPhoneNumber } else { 'Not configured' }
            $Email = if ($BrandingProfile.contactITEmailAddress) { $BrandingProfile.contactITEmailAddress } else { 'Not configured' }
            $null = $ResultMarkdown.Append("| [$($BrandingProfile.profileName)](https://intune.microsoft.com/#view/Microsoft_Intune_DeviceSettings/TenantAdminMenu/~/companyPortalBranding) | $Default | $DisplayName | $Phone | $Email |`n")
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown "$ResultMarkdown" -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Tenant'
    }
}
