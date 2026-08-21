function Invoke-CIPPBaselineCustomBannedPasswordList {
    <#
    .SYNOPSIS
        CustomBannedPasswordList executor: merges the configured words into the banned
        password list and enables the check.
    .DESCRIPTION
        The classic's additive merge: missing words prepend to the tenant's current list,
        deduplicated and capped at Entra's 1000, tab-joined on the wire. Creating from
        scratch carries the classic's defaults for the sibling lockout values; updating
        PATCHes only the check flag and the list so the SmartLockout standard's values are
        never touched.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Missing = @($Current.missingBannedWords | Where-Object { $_ })
    if ($Missing.Count -eq 0 -and $Current.bannedPasswordCheckEnabled -eq $true) { return }

    $AllWords = @(@($Missing) + @($Current.currentWords) | Where-Object { $_ } | Select-Object -Unique -First 1000)
    $ListValue = $AllWords -join ([char]9)

    # Always read the object LIVE: a cached id can be mid-rewrite stale (concurrent
    # one-offs share this object), the merge must include the live words so nothing drops,
    # and the update must resend EVERY template value - Graph rejects a partial values
    # array - so the lockout values come from the live object rather than this standard
    # guessing them.
    $Live = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/settings' -tenantid $TenantFilter) | Where-Object { "$($_.templateId)" -eq '5cf42378-d67d-4f36-ba46-e8b86229381d' } | Select-Object -First 1
    if ($Live) {
        $LiveWords = @("$((@($Live.values) | Where-Object { $_.name -eq 'BannedPasswordList' }).value)" -split ([char]9) | Where-Object { $_ })
        $AllWords = @(@($Missing) + @($LiveWords) | Where-Object { $_ } | Select-Object -Unique -First 1000)
        $ListValue = $AllWords -join ([char]9)
        $LiveValueOf = { param($Name, $Fallback) $Value = "$((@($Live.values) | Where-Object { $_.name -eq $Name }).value)"; if ([string]::IsNullOrWhiteSpace($Value)) { $Fallback } else { $Value } }
        $Body = @{ values = @(
                @{ name = 'EnableBannedPasswordCheck'; value = 'True' }
                @{ name = 'BannedPasswordList'; value = $ListValue }
                @{ name = 'LockoutDurationInSeconds'; value = (& $LiveValueOf 'LockoutDurationInSeconds' '60') }
                @{ name = 'LockoutThreshold'; value = (& $LiveValueOf 'LockoutThreshold' '10') }
                @{ name = 'EnableBannedPasswordCheckOnPremises'; value = (& $LiveValueOf 'EnableBannedPasswordCheckOnPremises' 'False') }
                @{ name = 'BannedPasswordCheckOnPremisesMode'; value = (& $LiveValueOf 'BannedPasswordCheckOnPremisesMode' 'Audit') }
            ) } | ConvertTo-Json -Depth 10 -Compress
        $null = New-GraphPostRequest -tenantid $TenantFilter -uri "https://graph.microsoft.com/beta/settings/$($Live.id)" -type PATCH -body $Body
    } else {
        $Body = @{
            templateId = '5cf42378-d67d-4f36-ba46-e8b86229381d'
            values     = @(
                @{ name = 'EnableBannedPasswordCheck'; value = 'True' }
                @{ name = 'BannedPasswordList'; value = $ListValue }
                @{ name = 'LockoutDurationInSeconds'; value = '60' }
                @{ name = 'LockoutThreshold'; value = '10' }
                @{ name = 'EnableBannedPasswordCheckOnPremises'; value = 'False' }
                @{ name = 'BannedPasswordCheckOnPremisesMode'; value = 'Audit' }
            )
        } | ConvertTo-Json -Depth 10 -Compress
        $null = New-GraphPostRequest -tenantid $TenantFilter -uri 'https://graph.microsoft.com/beta/settings' -type POST -body $Body
    }
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Banned password list: added $($Missing.Count) word(s), list now $($AllWords.Count)." -Sev 'Info'
}
