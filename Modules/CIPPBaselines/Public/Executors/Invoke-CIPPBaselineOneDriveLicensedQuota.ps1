function Invoke-CIPPBaselineOneDriveLicensedQuota {
    <#
    .SYNOPSIS
        OneDriveLicensedQuota executor: raises each offending personal site to 5 TB (warning at 90%).
    .DESCRIPTION
        One concurrent Set-CIPPSPOSiteBulk batch over the hook's targets, app-only with the SAM
        certificate as the classic did. Continues past per-site failures and throws only when
        every write failed.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    if ($null -eq $Current) { throw 'OneDriveLicensedQuota: no OneDrive quota data to remediate from.' }
    $Targets = @($Current.targets | Where-Object { $_.siteUrl })
    if ($Targets.Count -eq 0) { return }

    $TargetQuotaMB = [int64](5TB / 1MB)
    $WarningLevelMB = [int64]($TargetQuotaMB * 0.9)
    $BulkSites = @($Targets | ForEach-Object { @{ SiteUrl = $_.siteUrl; Properties = @{ StorageMaximumLevel = $TargetQuotaMB; StorageWarningLevel = $WarningLevelMB } } })
    $Results = @(Set-CIPPSPOSiteBulk -TenantFilter $TenantFilter -Sites $BulkSites -UseCertificate)
    $ResultByUrl = @{}
    foreach ($Result in $Results) { $ResultByUrl["$($Result.SiteUrl)"] = $Result }

    $Failed = 0
    foreach ($Target in $Targets) {
        $Result = $ResultByUrl["$($Target.siteUrl)"]
        if ($Result -and $Result.Success) {
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Raised OneDrive quota for $($Target.userPrincipalName) from $($Target.currentQuotaGB)GB to $($Target.targetQuotaGB)GB" -Sev 'Info'
        } else {
            $Failed++
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Failed to raise OneDrive quota for $($Target.userPrincipalName): $($Result.Error)" -Sev 'Error'
        }
    }
    if ($Failed -eq $Targets.Count) {
        throw "OneDriveLicensedQuota: all $Failed quota writes failed."
    }
}
