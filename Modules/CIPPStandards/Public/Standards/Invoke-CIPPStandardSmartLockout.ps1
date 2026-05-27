function Invoke-CIPPStandardSmartLockout {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) SmartLockout
    .SYNOPSIS
        (Label) Configure Entra ID Smart Lockout
    .DESCRIPTION
        (Helptext) **Requires Entra ID P1.** Configures the Entra ID Smart Lockout settings including lockout duration, lockout threshold, and on-premises integration mode.
        (DocsDescription) Configures the Entra ID Smart Lockout policy which protects against brute-force password attacks. Smart Lockout locks out bad actors who try to guess user passwords or use brute-force methods. It recognizes sign-ins from valid users and treats them differently from attackers. Settings include lockout duration (seconds), lockout threshold (failed attempts before lockout), and on-premises password protection mode (Audit or Enforced).
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "EIDSCAPR05"
            "EIDSCAPR06"
        ADDEDCOMPONENT
            {"type":"number","name":"standards.SmartLockout.LockoutDurationInSeconds","label":"Lockout Duration (seconds)","default":60,"required":true}
            {"type":"number","name":"standards.SmartLockout.LockoutThreshold","label":"Lockout Threshold (failed attempts)","default":10,"required":true}
            {"type":"switch","name":"standards.SmartLockout.EnableBannedPasswordCheckOnPremises","label":"Enable On-Premises Password Protection"}
            {"type":"radio","name":"standards.SmartLockout.BannedPasswordCheckOnPremisesMode","label":"On-Premises Mode","options":[{"label":"Audit","value":"Audit"},{"label":"Enforced","value":"Enforced"}]}
        IMPACT
            Medium Impact
        ADDEDDATE
            2025-05-27
        POWERSHELLEQUIVALENT
            Get-MgBetaDirectorySetting, New-MgBetaDirectorySetting, Update-MgBetaDirectorySetting
        RECOMMENDEDBY
            "CIS"
        REQUIREDCAPABILITIES
            "AAD_PREMIUM"
            "AAD_PREMIUM_P2"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)

    $TestResult = Test-CIPPStandardLicense -StandardName 'SmartLockout' -TenantFilter $Tenant -Preset Entra

    if ($TestResult -eq $false) {
        return $true
    }

    $PasswordRuleTemplateId = '5cf42378-d67d-4f36-ba46-e8b86229381d'

    # Extract desired values from settings
    $DesiredLockoutDuration = [string]($Settings.LockoutDurationInSeconds.value ?? $Settings.LockoutDurationInSeconds ?? '60')
    $DesiredLockoutThreshold = [string]($Settings.LockoutThreshold.value ?? $Settings.LockoutThreshold ?? '10')
    $DesiredEnableOnPrem = [string]($Settings.EnableBannedPasswordCheckOnPremises.value ?? $Settings.EnableBannedPasswordCheckOnPremises ?? 'False')
    $DesiredOnPremMode = $Settings.BannedPasswordCheckOnPremisesMode.value ?? $Settings.BannedPasswordCheckOnPremisesMode ?? 'Audit'

    # Normalize boolean switch to string
    if ($DesiredEnableOnPrem -eq $true -or $DesiredEnableOnPrem -eq 'true' -or $DesiredEnableOnPrem -eq 'True') {
        $DesiredEnableOnPrem = 'True'
    } else {
        $DesiredEnableOnPrem = 'False'
    }

    # Get existing directory settings for password rules
    try {
        $ExistingSettings = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/settings' -tenantid $Tenant | Where-Object { $_.templateId -eq $PasswordRuleTemplateId }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to get Smart Lockout settings: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return
    }

    # Extract current values
    if ($null -ne $ExistingSettings) {
        $CurrentLockoutDuration = ($ExistingSettings.values | Where-Object { $_.name -eq 'LockoutDurationInSeconds' }).value
        $CurrentLockoutThreshold = ($ExistingSettings.values | Where-Object { $_.name -eq 'LockoutThreshold' }).value
        $CurrentEnableOnPrem = ($ExistingSettings.values | Where-Object { $_.name -eq 'EnableBannedPasswordCheckOnPremises' }).value
        $CurrentOnPremMode = ($ExistingSettings.values | Where-Object { $_.name -eq 'BannedPasswordCheckOnPremisesMode' }).value
    }

    $StateIsCorrect = $null -ne $ExistingSettings -and
    $CurrentLockoutDuration -eq $DesiredLockoutDuration -and
    $CurrentLockoutThreshold -eq $DesiredLockoutThreshold -and
    $CurrentEnableOnPrem -eq $DesiredEnableOnPrem -and
    $CurrentOnPremMode -eq $DesiredOnPremMode

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Smart Lockout is already configured correctly.' -sev Info
        } else {
            try {
                if ($null -eq $ExistingSettings) {
                    # Create new directory setting with desired values
                    $Body = @{
                        templateId = $PasswordRuleTemplateId
                        values     = @(
                            @{ name = 'EnableBannedPasswordCheck'; value = 'False' }
                            @{ name = 'BannedPasswordList'; value = '' }
                            @{ name = 'LockoutDurationInSeconds'; value = $DesiredLockoutDuration }
                            @{ name = 'LockoutThreshold'; value = $DesiredLockoutThreshold }
                            @{ name = 'EnableBannedPasswordCheckOnPremises'; value = $DesiredEnableOnPrem }
                            @{ name = 'BannedPasswordCheckOnPremisesMode'; value = $DesiredOnPremMode }
                        )
                    }
                    $JsonBody = ConvertTo-Json -Depth 10 -InputObject $Body -Compress
                    $null = New-GraphPostRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/beta/settings' -Type POST -Body $JsonBody
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Smart Lockout created: Duration=$DesiredLockoutDuration, Threshold=$DesiredLockoutThreshold, OnPrem=$DesiredEnableOnPrem, Mode=$DesiredOnPremMode" -sev Info
                } else {
                    # Update existing directory setting, preserving banned password list values
                    $CurrentBannedPasswordCheck = ($ExistingSettings.values | Where-Object { $_.name -eq 'EnableBannedPasswordCheck' }).value
                    $CurrentBannedPasswordList = ($ExistingSettings.values | Where-Object { $_.name -eq 'BannedPasswordList' }).value

                    $Body = @{
                        values = @(
                            @{ name = 'EnableBannedPasswordCheck'; value = $CurrentBannedPasswordCheck }
                            @{ name = 'BannedPasswordList'; value = $CurrentBannedPasswordList }
                            @{ name = 'LockoutDurationInSeconds'; value = $DesiredLockoutDuration }
                            @{ name = 'LockoutThreshold'; value = $DesiredLockoutThreshold }
                            @{ name = 'EnableBannedPasswordCheckOnPremises'; value = $DesiredEnableOnPrem }
                            @{ name = 'BannedPasswordCheckOnPremisesMode'; value = $DesiredOnPremMode }
                        )
                    }
                    $JsonBody = ConvertTo-Json -Depth 10 -InputObject $Body -Compress
                    $null = New-GraphPostRequest -tenantid $Tenant -Uri "https://graph.microsoft.com/beta/settings/$($ExistingSettings.id)" -Type PATCH -Body $JsonBody
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Smart Lockout updated: Duration=$DesiredLockoutDuration, Threshold=$DesiredLockoutThreshold, OnPrem=$DesiredEnableOnPrem, Mode=$DesiredOnPremMode" -sev Info
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to configure Smart Lockout: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'Smart Lockout is compliant.' -sev Info
        } else {
            $AlertObject = @{
                LockoutDurationInSeconds            = $CurrentLockoutDuration ?? 'Not Configured'
                LockoutThreshold                    = $CurrentLockoutThreshold ?? 'Not Configured'
                EnableBannedPasswordCheckOnPremises = $CurrentEnableOnPrem ?? 'Not Configured'
                BannedPasswordCheckOnPremisesMode   = $CurrentOnPremMode ?? 'Not Configured'
                DesiredLockoutDurationInSeconds     = $DesiredLockoutDuration
                DesiredLockoutThreshold             = $DesiredLockoutThreshold
                DesiredEnableOnPrem                 = $DesiredEnableOnPrem
                DesiredOnPremMode                   = $DesiredOnPremMode
            }
            Write-StandardsAlert -message 'Smart Lockout is not configured correctly' -object $AlertObject -tenant $Tenant -standardName 'SmartLockout' -standardId $Settings.standardId
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = @{
            LockoutDurationInSeconds            = $CurrentLockoutDuration ?? 'Not Configured'
            LockoutThreshold                    = $CurrentLockoutThreshold ?? 'Not Configured'
            EnableBannedPasswordCheckOnPremises = $CurrentEnableOnPrem ?? 'Not Configured'
            BannedPasswordCheckOnPremisesMode   = $CurrentOnPremMode ?? 'Not Configured'
        }
        $ExpectedValue = @{
            LockoutDurationInSeconds            = $DesiredLockoutDuration
            LockoutThreshold                    = $DesiredLockoutThreshold
            EnableBannedPasswordCheckOnPremises = $DesiredEnableOnPrem
            BannedPasswordCheckOnPremisesMode   = $DesiredOnPremMode
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.SmartLockout' `
            -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant

        Add-CIPPBPAField -FieldName 'SmartLockout' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $Tenant
    }
}
