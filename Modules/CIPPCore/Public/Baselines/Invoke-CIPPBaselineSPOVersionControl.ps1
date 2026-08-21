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

    $State = Get-CIPPSPOTenant -TenantFilter $TenantFilter | Select-Object -Property _ObjectIdentity_, TenantFilter
    if (-not $State) { throw 'Could not read the SPO tenant configuration - refusing a blind write.' }

    $MethodParams = if ($AutoTrim) {
        @(@{ Type = 'Boolean'; Value = $true }, @{ Type = 'Int32'; Value = -1 }, @{ Type = 'Int32'; Value = -1 })
    } else {
        @(@{ Type = 'Boolean'; Value = $false }, @{ Type = 'Int32'; Value = $MajorLimit }, @{ Type = 'Int32'; Value = $ExpireDays })
    }
    $State | Set-CIPPSPOTenant -MethodName 'SetFileVersionPolicy' -MethodParameters $MethodParams
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
        $Failures = 0
        foreach ($Site in $Sites) {
            try {
                Set-CIPPSPOSite -TenantFilter $TenantFilter -SiteUrl $Site.webUrl -Properties $SiteProperties
            } catch {
                $Failures++
                Write-Information "Baselines: version policy on $($Site.webUrl) continued past: $($_.Exception.Message)"
            }
        }
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Applied the version policy to $(@($Sites).Count - $Failures) of $(@($Sites).Count) existing site(s)." -Sev 'Info'
    }
}
