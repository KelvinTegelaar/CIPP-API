function Invoke-CippTestZTNA21889 {
    <#
    .SYNOPSIS
    Checks if organization has reduced password surface area by enabling multiple passwordless authentication methods

    .DESCRIPTION
    Verifies that both FIDO2 Security Keys and Microsoft Authenticator are enabled with proper configuration
    to reduce reliance on passwords.

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tenant
    )
    #tested
    try {
        # Get authentication methods policy from cache
        $AuthMethodsPolicy = New-CIPPDbRequest -TenantFilter $Tenant -Type 'AuthenticationMethodsPolicy'

        if (-not $AuthMethodsPolicy) {
            $TestParams = @{
                TestId = 'ZTNA21889'
                TenantFilter = $Tenant
                TestType = 'ZeroTrustNetworkAccess'
                Status = 'Skipped'
                ResultMarkdown = 'Unable to retrieve authentication methods policy from cache.'
                Risk = 'High'
                Name = 'Reduce the user-visible password surface area'
                UserImpact = 'Medium'
                ImplementationEffort = 'Medium'
                Category = 'Access control'
            }
            Add-CippTestResult @TestParams
            return
        }

        # Extract FIDO2 and Microsoft Authenticator configurations
        $Fido2Config = $null
        $AuthenticatorConfig = $null

        if ($AuthMethodsPolicy.authenticationMethodConfigurations) {
            foreach ($config in $AuthMethodsPolicy.authenticationMethodConfigurations) {
                if ($config.id -eq 'Fido2') {
                    $Fido2Config = $config
                }
                if ($config.id -eq 'MicrosoftAuthenticator') {
                    $AuthenticatorConfig = $config
                }
            }
        }

        # Check FIDO2 configuration
        $Fido2Enabled = $Fido2Config.state -eq 'enabled'
        $Fido2HasTargets = $Fido2Config.includeTargets -and $Fido2Config.includeTargets.Count -gt 0
        $Fido2Valid = $Fido2Enabled -and $Fido2HasTargets

        # Check Microsoft Authenticator configuration
        $AuthEnabled = $AuthenticatorConfig.state -eq 'enabled'
        $AuthHasTargets = $AuthenticatorConfig.includeTargets -and $AuthenticatorConfig.includeTargets.Count -gt 0
        $AuthMode = $null
        if ($AuthenticatorConfig.includeTargets) {
            foreach ($target in $AuthenticatorConfig.includeTargets) {
                if ($target.authenticationMode) {
                    $AuthMode = $target.authenticationMode
                    break
                }
            }
        }

        if ([string]::IsNullOrEmpty($AuthMode)) {
            $AuthMode = 'Not configured'
            $AuthModeValid = $false
        } else {
            $AuthModeValid = ($AuthMode -eq 'any') -or ($AuthMode -eq 'deviceBasedPush')
        }
        $AuthValid = $AuthEnabled -and $AuthHasTargets -and $AuthModeValid

        # Determine pass/fail
        $Status = if ($Fido2Valid -and $AuthValid) { 'Passed' } else { 'Failed' }

        # Build result message
        if ($Status -eq 'Passed') {
            $ResultMarkdown = "✅ **Pass**: Your organization has implemented multiple passwordless authentication methods reducing password exposure.`n`n"
        } else {
            $ResultMarkdown = "❌ **Fail**: Your organization relies heavily on password-based authentication, creating security vulnerabilities.`n`n"
        }

        # Build detailed markdown table
        $ResultMarkdown += "## Passwordless authentication methods`n`n"
        $ResultMarkdown += "| Method | State | Include targets | Authentication mode | Status |`n"
        $ResultMarkdown += "| :----- | :---- | :-------------- | :------------------ | :----- |`n"

        # FIDO2 row
        $Fido2State = if ($Fido2Enabled) { '✅ Enabled' } else { '❌ Disabled' }
        $Fido2TargetsDisplay = if ($Fido2Config.includeTargets -and $Fido2Config.includeTargets.Count -gt 0) {
            "$($Fido2Config.includeTargets.Count) target(s)"
        } else {
            'None'
        }
        $Fido2Status = if ($Fido2Valid) { '✅ Pass' } else { '❌ Fail' }
        $ResultMarkdown += "| FIDO2 Security Keys | $Fido2State | $Fido2TargetsDisplay | N/A | $Fido2Status |`n"

        # Microsoft Authenticator row
        $AuthState = if ($AuthEnabled) { '✅ Enabled' } else { '❌ Disabled' }
        $AuthTargetsDisplay = if ($AuthenticatorConfig.includeTargets -and $AuthenticatorConfig.includeTargets.Count -gt 0) {
            "$($AuthenticatorConfig.includeTargets.Count) target(s)"
        } else {
            'None'
        }
        $AuthModeDisplay = if ($AuthModeValid) { "✅ $AuthMode" } else { "❌ $AuthMode" }
        $AuthStatus = if ($AuthValid) { '✅ Pass' } else { '❌ Fail' }
        $ResultMarkdown += "| Microsoft Authenticator | $AuthState | $AuthTargetsDisplay | $AuthModeDisplay | $AuthStatus |`n"

        $TestParams = @{
            TestId = 'ZTNA21889'
            TenantFilter = $Tenant
            TestType = 'ZeroTrustNetworkAccess'
            Status = $Status
            ResultMarkdown = $ResultMarkdown
            Risk = 'High'
            Name = 'Reduce the user-visible password surface area'
            UserImpact = 'Medium'
            ImplementationEffort = 'Medium'
            Category = 'Access control'
        }
        Add-CippTestResult @TestParams

    } catch {
        $TestParams = @{
            TestId = 'ZTNA21889'
            TenantFilter = $Tenant
            TestType = 'ZeroTrustNetworkAccess'
            Status = 'Failed'
            ResultMarkdown = "❌ **Error**: $($_.Exception.Message)"
            Risk = 'High'
            Name = 'Reduce the user-visible password surface area'
            UserImpact = 'Medium'
            ImplementationEffort = 'Medium'
            Category = 'Access control'
        }
        Add-CippTestResult @TestParams
        Write-LogMessage -API 'ZeroTrustNetworkAccess' -tenant $Tenant -message "Test ZTNA21889 failed: $($_.Exception.Message)" -sev Error
    }
}
