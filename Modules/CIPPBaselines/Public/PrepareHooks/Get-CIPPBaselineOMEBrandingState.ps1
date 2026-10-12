function Get-CIPPBaselineOMEBrandingState {
    <#
    .SYNOPSIS
        Prepare hook for OMEBranding: encrypted-message branding configuration.
    .DESCRIPTION
        Grades only the fields the operator configured - an empty branding field expresses
        no opinion, and grading it would strip existing branding on remediation. That
        only-if-specified rule is the classic's own.

        A configured logo grades as permanent drift, exactly as the classic behaved: the
        tenant never exposes the current image bytes, so the logo cannot be compared, and
        the classic re-uploaded it on every remediation run. The drift row names logoApplied
        so the operator can see why the row never settles while a logo is configured.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Configs = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoOMEConfiguration')
    if ($Configs.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'ExoOMEConfiguration')) {
        return @{ Current = $null }
    }
    $Config = @($Configs | Where-Object { "$($_.Identity)" -eq 'OME Configuration' }) | Select-Object -First 1
    if (-not $Config) { $Config = $Configs | Select-Object -First 1 }

    $V = $Item.Variables
    $Expected = [PSCustomObject]@{}
    $Current = [PSCustomObject]@{}
    foreach ($Field in @('BackgroundColor', 'EmailText', 'IntroductionText', 'ReadButtonText', 'PortalText', 'DisclaimerText', 'PrivacyStatementUrl')) {
        if ([string]::IsNullOrWhiteSpace("$($V.$Field)")) { continue }
        $Expected | Add-Member -NotePropertyName $Field -NotePropertyValue "$($V.$Field)"
        $Current | Add-Member -NotePropertyName $Field -NotePropertyValue "$($Config.$Field)"
    }
    foreach ($Switch in @('OTPEnabled', 'SocialIdSignIn')) {
        $Value = $V.$Switch
        if ($Value -is [System.Management.Automation.PSCustomObject] -and $Value.PSObject.Properties.Name -contains 'value') { $Value = $Value.value }
        if ($null -eq $Value -or "$Value" -eq '') { continue }
        $Expected | Add-Member -NotePropertyName $Switch -NotePropertyValue ([bool]($Value -eq $true -or "$Value" -eq 'True'))
        $Current | Add-Member -NotePropertyName $Switch -NotePropertyValue ([bool]$Config.$Switch)
    }
    if (-not [string]::IsNullOrWhiteSpace("$($V.LogoUrl)")) {
        # The image cannot be read back, so a configured logo is permanent drift - the
        # classic's exact behaviour, made visible.
        $Expected | Add-Member -NotePropertyName 'logoApplied' -NotePropertyValue $true
        $Current | Add-Member -NotePropertyName 'logoApplied' -NotePropertyValue $false
    }

    if (@($Expected.PSObject.Properties).Count -eq 0) { return @{ Current = $null } }

    $Current | Add-Member -NotePropertyName 'omeIdentity' -NotePropertyValue "$($Config.Identity ?? 'OME Configuration')"

    @{ Expected = $Expected; Current = $Current }
}
