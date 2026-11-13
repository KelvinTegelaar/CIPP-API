function Invoke-CippTestZTNA35008 {
    <#
    .SYNOPSIS
    Default sensitivity labels are configured for SharePoint document libraries
    #>
    param($Tenant)

    $TestParams = @{ TenantFilter = $Tenant; TestId = 'ZTNA35008'; TestType = 'Identity'; Name = 'Default sensitivity labels are configured for SharePoint document libraries'; Risk = 'Medium'; UserImpact = 'Low'; ImplementationEffort = 'Low'; Category = 'SharePoint Online' }
    try {
        if (-not (Test-CIPPStandardLicense -StandardName 'ZTNA35008' -TenantFilter $Tenant -RequiredCapabilities @('RMS_S_PREMIUM2') -SkipLog)) {
            Add-CippTestResult @TestParams -Status 'Unlicensed' -ResultMarkdown 'This tenant is not licensed for Microsoft Purview Information Protection P2. Required capability: RMS_S_PREMIUM2.'
            return
        }

        $SPOTenant = @(Get-CIPPTestData -TenantFilter $Tenant -Type 'SPOTenant')[0]
        if (-not $SPOTenant) {
            Add-CippTestResult @TestParams -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.'
            return
        }

        $Disabled = $SPOTenant.DisableDocumentLibraryDefaultLabeling -eq $true
        $Status, $Headline = if ($Disabled) {
            'Failed', '❌ Default sensitivity label capability is DISABLED. Site admins cannot configure library-level default labels.'
        } else {
            'Passed', '✅ Default sensitivity label capability is enabled for SharePoint document libraries, allowing automatic baseline labeling.'
        }
        $Result = "$Headline`n`n### SharePoint Online Configuration Summary`n`n**Tenant Settings:**`n* DisableDocumentLibraryDefaultLabeling: $Disabled"

        Add-CippTestResult @TestParams -Status $Status -ResultMarkdown $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult @TestParams -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)"
    }
}
