function Invoke-CippTestZTNA21846 {
    <#
    .SYNOPSIS
    Restrict Temporary Access Pass to Single Use
    #>
    param($Tenant)

    $TestId = 'ZTNA21846'
    #Tested
    try {
        # Get Temporary Access Pass configuration
        $AuthMethodsPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'
        $TAPConfig = $AuthMethodsPolicy.authenticationMethodConfigurations | Where-Object { $_.id -eq 'TemporaryAccessPass' }

        if (-not $TAPConfig) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'Medium' -Name 'Restrict Temporary Access Pass to Single Use' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'
            return
        }

        $Passed = if ($TAPConfig.isUsableOnce -eq $true) { 'Passed' } else { 'Failed' }

        if ($Passed -eq 'Passed') {
            $ResultMarkdown = "Temporary Access Pass is configured for one-time use only.`n`n"
        } else {
            $ResultMarkdown = "Temporary Access Pass allows multiple uses during validity period.`n`n"
        }

        $ResultMarkdown += "## Temporary Access Pass Configuration`n`n"
        $ResultMarkdown += "| Setting | Value | Status |`n"
        $ResultMarkdown += "| :------ | :---- | :----- |`n"

        $IsUsableOnceValue = if ($TAPConfig.isUsableOnce) { 'Enabled' } else { 'Disabled' }
        $StatusEmoji = if ($Passed -eq 'Passed') { '✅ Pass' } else { '❌ Fail' }

        $ResultMarkdown += "| [One-time use restriction](https://entra.microsoft.com/#view/Microsoft_AAD_IAM/AuthenticationMethodsMenuBlade/~/AdminAuthMethods/fromNav/) | $IsUsableOnceValue | $StatusEmoji |`n"

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'Medium' -Name 'Restrict Temporary Access Pass to Single Use' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name 'Restrict Temporary Access Pass to Single Use' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Credential management'
    }
}
