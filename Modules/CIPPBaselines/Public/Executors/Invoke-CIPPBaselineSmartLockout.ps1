function Invoke-CIPPBaselineSmartLockout {
    <#
    .SYNOPSIS
        SmartLockout executor: writes the lockout values on the password-rule directory
        setting.
    .DESCRIPTION
        Creates the setting object with the classic's defaults when the tenant has none;
        otherwise PATCHes the FULL six-value array - Graph rejects a directory-settings
        update that omits any template property - with the banned-password values taken
        from the LIVE object so this standard never steps on CustomBannedPasswordList's
        territory.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Mode = "$($Remediate.bannedPasswordCheckOnPremisesMode)"
    if ($Mode -eq 'Enforced') { $Mode = 'Enforce' }
    if ([string]::IsNullOrWhiteSpace($Mode)) { $Mode = 'Audit' }
    $OnPrem = if ($Remediate.enableBannedPasswordCheckOnPremises -eq $true -or "$($Remediate.enableBannedPasswordCheckOnPremises)" -eq 'True') { 'True' } else { 'False' }
    $LockoutValues = @(
        @{ name = 'LockoutDurationInSeconds'; value = "$($Remediate.lockoutDurationInSeconds)" }
        @{ name = 'LockoutThreshold'; value = "$($Remediate.lockoutThreshold)" }
        @{ name = 'EnableBannedPasswordCheckOnPremises'; value = $OnPrem }
        @{ name = 'BannedPasswordCheckOnPremisesMode'; value = $Mode }
    )

    # Always read the object LIVE: a cached id can be mid-rewrite stale (concurrent
    # one-offs share this object), and the update must resend EVERY template value - Graph
    # rejects a partial values array - so the banned-password values come from the live
    # object rather than this standard guessing them.
    $Live = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/settings' -tenantid $TenantFilter) | Where-Object { "$($_.templateId)" -eq '5cf42378-d67d-4f36-ba46-e8b86229381d' } | Select-Object -First 1
    if (-not $Live) {
        $Body = @{
            templateId = '5cf42378-d67d-4f36-ba46-e8b86229381d'
            values     = @(@(
                    @{ name = 'EnableBannedPasswordCheck'; value = 'False' }
                    @{ name = 'BannedPasswordList'; value = '' }
                ) + $LockoutValues)
        } | ConvertTo-Json -Depth 10 -Compress
        $null = New-GraphPostRequest -tenantid $TenantFilter -uri 'https://graph.microsoft.com/beta/settings' -type POST -body $Body
    } else {
        $LiveValueOf = { param($Name) "$((@($Live.values) | Where-Object { $_.name -eq $Name }).value)" }
        $Body = @{ values = @(@(
                    @{ name = 'EnableBannedPasswordCheck'; value = (& $LiveValueOf 'EnableBannedPasswordCheck') }
                    @{ name = 'BannedPasswordList'; value = (& $LiveValueOf 'BannedPasswordList') }
                ) + $LockoutValues) } | ConvertTo-Json -Depth 10 -Compress
        $null = New-GraphPostRequest -tenantid $TenantFilter -uri "https://graph.microsoft.com/beta/settings/$($Live.id)" -type PATCH -body $Body
    }
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Applied smart lockout: $($Remediate.lockoutThreshold) attempts, $($Remediate.lockoutDurationInSeconds)s, on-prem $OnPrem/$Mode." -Sev 'Info'
}
