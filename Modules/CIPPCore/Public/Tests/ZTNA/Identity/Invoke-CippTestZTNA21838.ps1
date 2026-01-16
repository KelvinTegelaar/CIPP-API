function Invoke-CippTestZTNA21838 {
    <#
    .SYNOPSIS
    Security key authentication method enabled
    #>
    param($Tenant)

    $TestId = 'ZTNA21838'
    #Tested
    try {
        # Get FIDO2 authentication method policy
        $AuthMethodsPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AuthMethodsPolicy) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Security key authentication method enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Access control'
            return
        }

        $Fido2Config = $AuthMethodsPolicy.authenticationMethodConfigurations | Where-Object { $_.id -eq 'Fido2' }

        if (-not $Fido2Config) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Skipped' -ResultMarkdown 'No data found in database. This may be due to missing required licenses or data collection not yet completed.' -Risk 'High' -Name 'Security key authentication method enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Access control'
            return
        }

        $Fido2Enabled = $Fido2Config.state -eq 'enabled'
        $Passed = if ($Fido2Enabled) { 'Passed' } else { 'Failed' }
        $StatusEmoji = if ($Fido2Enabled) { '✅' } else { '❌' }

        if ($Fido2Enabled) {
            $ResultMarkdown = "Security key authentication method is enabled for your tenant, providing hardware-backed phishing-resistant authentication.`n`n"
        } else {
            $ResultMarkdown = "Security key authentication method is not enabled; users cannot register FIDO2 security keys for strong authentication.`n`n"
        }

        $ResultMarkdown += "## FIDO2 security key authentication settings`n`n"
        $ResultMarkdown += "$StatusEmoji **FIDO2 authentication method**`n"
        $ResultMarkdown += "- Status: $($Fido2Config.state)`n"

        $IncludeTargetsDisplay = if ($Fido2Config.includeTargets -and $Fido2Config.includeTargets.Count -gt 0) {
            ($Fido2Config.includeTargets | ForEach-Object { if ($_.id -eq 'all_users') { 'All users' } else { $_.id } }) -join ', '
        } else {
            'None'
        }
        $ResultMarkdown += "- Include targets: $IncludeTargetsDisplay`n"

        $ExcludeTargetsDisplay = if ($Fido2Config.excludeTargets -and $Fido2Config.excludeTargets.Count -gt 0) {
            ($Fido2Config.excludeTargets | ForEach-Object { $_.id }) -join ', '
        } else {
            'None'
        }
        $ResultMarkdown += "- Exclude targets: $ExcludeTargetsDisplay`n"

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status $Passed -ResultMarkdown $ResultMarkdown -Risk 'High' -Name 'Security key authentication method enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Access control'

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Failed to run test: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Identity' -Status 'Failed' -ResultMarkdown "Error running test: $($ErrorMessage.NormalizedError)" -Risk 'High' -Name 'Security key authentication method enabled' -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'Access control'
    }
}
