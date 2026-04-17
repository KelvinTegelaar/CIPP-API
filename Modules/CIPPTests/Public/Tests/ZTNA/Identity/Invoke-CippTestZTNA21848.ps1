function Invoke-CippTestZTNA21848 {
    <#
    .SYNOPSIS
    Add organizational terms to the banned password list
    #>
    param($Tenant)

    $TestId = 'ZTNA21848'
    #Tested
    try {
        # Get password protection settings from Settings cache
        $Settings = New-CIPPDbRequest -TenantFilter $Tenant -Type 'Settings'
        $PasswordProtectionSettings = $Settings | Where-Object { $_.templateId -eq '5cf42378-d67d-4f36-ba46-e8b86229381d' }

        if (-not $PasswordProtectionSettings) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Add organizational terms to the banned password list' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'
            return
        }

        $EnableBannedPasswordCheck = ($PasswordProtectionSettings.values | Where-Object { $_.name -eq 'EnableBannedPasswordCheck' }).value
        $BannedPasswordList = ($PasswordProtectionSettings.values | Where-Object { $_.name -eq 'BannedPasswordList' }).value

        if ([string]::IsNullOrEmpty($BannedPasswordList)) {
            $BannedPasswordList = $null
        }

        $Passed = if ($EnableBannedPasswordCheck -eq $true -and $null -ne $BannedPasswordList) { 'Passed' } else { 'Failed' }

        $PortalLink = 'https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/PasswordProtection/fromNav/'

        $Enforced = if ($EnableBannedPasswordCheck -eq $true) { 'Yes' } else { 'No' }

        # Split on tab characters to handle tab-delimited banned password entries
        if ($BannedPasswordList) {
            $BannedPasswordArray = $BannedPasswordList -split '\t'
        } else {
            $BannedPasswordArray = @()
        }

        # Show up to 10 banned passwords, summarize if more exist
        $MaxDisplay = 10
        if ($BannedPasswordArray.Count -gt $MaxDisplay) {
            $DisplayList = $BannedPasswordArray[0..($MaxDisplay - 1)] + "...and $($BannedPasswordArray.Count - $MaxDisplay) more"
        } else {
            $DisplayList = $BannedPasswordArray
        }

        if ($Passed -eq 'Passed') {
            $ResultMarkdown = "✅ Custom banned passwords are properly configured with organization-specific terms.`n`n"
        } else {
            $ResultMarkdown = "❌ Custom banned passwords are not enabled or lack organization-specific terms.`n`n"
        }

        $ResultMarkdown += "## [Password protection settings]($PortalLink)`n`n"
        $ResultMarkdown += "| Enforce custom list | Custom banned password list | Number of terms |`n"
        $ResultMarkdown += "| :------------------ | :-------------------------- | :-------------- |`n"
        $ResultMarkdown += "| $Enforced | $($DisplayList -join ', ') | $($BannedPasswordArray.Count) |`n"

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'Medium' -Name 'Add organizational terms to the banned password list' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Add organizational terms to the banned password list' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'
    }
}
