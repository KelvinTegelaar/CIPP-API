function Invoke-CIPPBaselineOMEBranding {
    <#
    .SYNOPSIS
        OMEBranding executor: applies the configured encrypted-message branding.
    .DESCRIPTION
        Writes only what the baseline configures - Set-OMEConfiguration treats absent
        parameters as leave-alone, so unspecified branding fields survive, mirroring the
        compare. The logo downloads fresh from the configured URL on every run, exactly as
        the classic did: the tenant cannot echo the image back, so re-upload is the only way
        to enforce it. A failed download skips the image but still writes the rest.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $SetParams = @{ Identity = "$($Current.omeIdentity ?? 'OME Configuration')" }
    foreach ($Field in @('BackgroundColor', 'EmailText', 'IntroductionText', 'ReadButtonText', 'PortalText', 'DisclaimerText', 'PrivacyStatementUrl')) {
        $Value = $Remediate.$($Field.Substring(0, 1).ToLower() + $Field.Substring(1))
        if (-not [string]::IsNullOrWhiteSpace("$Value")) { $SetParams[$Field] = "$Value" }
    }
    foreach ($Switch in @('OTPEnabled', 'SocialIdSignIn')) {
        $Value = $Remediate.$($Switch.Substring(0, 1).ToLower() + $Switch.Substring(1))
        if ($null -ne $Value -and "$Value" -ne '') { $SetParams[$Switch] = [bool]($Value -eq $true -or "$Value" -eq 'True') }
    }
    if (-not [string]::IsNullOrWhiteSpace("$($Remediate.logoUrl)") -and "$($Remediate.logoUrl)" -match '^https?://') {
        try {
            $SetParams['Image'] = (Invoke-WebRequest -Uri "$($Remediate.logoUrl)" -UseBasicParsing).Content
        } catch {
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Could not download the OME logo from $($Remediate.logoUrl): $($_.Exception.Message) - applying the rest of the branding without it." -Sev 'Error'
        }
    }

    if ($SetParams.Count -le 1) { return }
    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-OMEConfiguration' -cmdParams $SetParams -useSystemMailbox $true
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Applied OME branding configuration.' -Sev 'Info'
}
