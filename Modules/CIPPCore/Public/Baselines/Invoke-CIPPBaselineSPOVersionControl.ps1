function Invoke-CIPPBaselineSPOVersionControl {
    <#
    .SYNOPSIS
        SPOVersionControl executor: writes the tenant file version policy, optionally
        pushing it to existing sites.
    .DESCRIPTION
        The tenant write goes through the SPO SetFileVersionPolicy method with the
        classic's exact parameter shape (-1 sentinels for the limits when auto-trim is on),
        against a LIVE-read CSOM identity. When the baseline opts into existing sites, each
        site inherits the tenant policy across new and existing document libraries - a
        per-site fan-out that continues past individual site failures, as the classic did.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $AutoTrim = [bool]($Remediate.enableAutoTrim -eq $true -or "$($Remediate.enableAutoTrim)" -eq 'True')
    $MajorLimit = [int]"$($Remediate.majorVersionLimit ?? 50)"
    $ExpireDays = [int]"$($Remediate.expireVersionsAfterDays ?? 0)"
    if (-not $AutoTrim -and $ExpireDays -ne 0 -and ($ExpireDays -lt 30 -or $ExpireDays -gt 36500)) { return }

    # SharePoint app-only requires the SAM certificate; delegated is not available on every tenant.
    $State = Get-CIPPSPOTenant -TenantFilter $TenantFilter -UseCertificate | Select-Object -Property _ObjectIdentity_, TenantFilter
    if (-not $State) { throw 'Could not read the SPO tenant configuration - refusing a blind write.' }

    $MethodParams = if ($AutoTrim) {
        @(@{ Type = 'Boolean'; Value = $true }, @{ Type = 'Int32'; Value = -1 }, @{ Type = 'Int32'; Value = -1 })
    } else {
        @(@{ Type = 'Boolean'; Value = $false }, @{ Type = 'Int32'; Value = $MajorLimit }, @{ Type = 'Int32'; Value = $ExpireDays })
    }
    $State | Set-CIPPSPOTenant -MethodName 'SetFileVersionPolicy' -MethodParameters $MethodParams -UseCertificate
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Set the file version policy (autoTrim=$AutoTrim$(if (-not $AutoTrim) { ", limit=$MajorLimit, expire=${ExpireDays}d" }))." -Sev 'Info'

    if ($Remediate.applyToExistingSites -eq $true -or "$($Remediate.applyToExistingSites)" -eq 'True') {
        $Sites = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/getAllSites?`$select=webUrl&`$top=999" -tenantid $TenantFilter -AsApp $true)
        $SiteProperties = @{
            InheritVersionPolicyFromTenant   = $true
            EnableAutoExpirationVersionTrim  = $AutoTrim
            ApplyToNewDocumentLibraries      = $true
            ApplyToExistingDocumentLibraries = $true
        }
        if (-not $AutoTrim) {
            $SiteProperties.MajorVersionLimit = $MajorLimit
            $SiteProperties.ExpireVersionsAfterDays = $ExpireDays
        }
        # One concurrent batch (Set-CIPPSPOSiteBulk fans out in .NET) instead of ~2s per site.
        $BulkSites = @($Sites | ForEach-Object { @{ SiteUrl = $_.webUrl; Properties = $SiteProperties } })
        $BulkResults = @(Set-CIPPSPOSiteBulk -TenantFilter $TenantFilter -Sites $BulkSites -UseCertificate)
        $Failures = @($BulkResults | Where-Object { -not $_.Success })
        foreach ($FailedSite in $Failures) {
            Write-Information "Baselines: version policy on $($FailedSite.SiteUrl) continued past: $($FailedSite.Error)"
        }
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Applied the version policy to $(@($Sites).Count - $Failures.Count) of $(@($Sites).Count) existing site(s)." -Sev 'Info'
    }
}
