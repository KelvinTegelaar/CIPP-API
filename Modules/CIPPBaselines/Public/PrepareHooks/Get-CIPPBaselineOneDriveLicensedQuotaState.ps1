function Get-CIPPBaselineOneDriveLicensedQuotaState {
    <#
    .SYNOPSIS
        Prepare hook for OneDriveLicensedQuota: entitled users whose OneDrive quota is below 5 TB.
    .DESCRIPTION
        Entitled users are enabled accounts holding an enabled SharePoint/OneDrive Plan 2 service
        plan, read from the Users cache. Microsoft only permits quotas above 1 TB once five users
        hold a qualifying plan, so below that the tenant is compliant. Quotas come from the
        OneDriveQuotas cache; a user without a provisioned drive has no row there and is skipped,
        as is a quota already at or above 5 TB.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Users = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'Users')
    if ($Users.Count -eq 0) { return @{ Current = $null; NoDataReason = 'the Users cache has no data for this tenant' } }

    $QualifyingPlanIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@(
            '5dbe027f-2339-4123-9542-606e4d348a72' # SHAREPOINTENTERPRISE
            '63038b2c-28d0-45f6-bc36-33062963b498' # SHAREPOINTENTERPRISE_EDU
            '153f85dd-d912-4762-af6c-d6e0fb4f6692' # SHAREPOINTENTERPRISE_GOV
            'afcafa6a-d966-4462-918c-ec0b4e0fe642' # ONEDRIVEENTERPRISE
        ), [System.StringComparer]::OrdinalIgnoreCase)
    $TargetQuotaBytes = 5TB

    $EntitledById = @{}
    foreach ($User in $Users) {
        if ($User.accountEnabled -ne $true -or -not $User.id) { continue }
        foreach ($Plan in @($User.assignedPlans)) {
            if ($Plan.capabilityStatus -eq 'Enabled' -and $QualifyingPlanIds.Contains("$($Plan.servicePlanId)")) {
                $EntitledById["$($User.id)"] = $User
                break
            }
        }
    }

    $Offenders = [System.Collections.Generic.List[object]]::new()
    if ($EntitledById.Count -ge 5) {
        if (-not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'OneDriveQuotas')) { return @{ Current = $null; NoDataReason = 'the OneDrive quotas cache could not be collected for this tenant' } }
        foreach ($Drive in @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'OneDriveQuotas')) {
            $User = $EntitledById["$($Drive.id)"]
            if (-not $User) { continue }
            $Total = [int64]($Drive.quotaTotal ?? 0)
            if ($Total -le 0 -or $Total -ge $TargetQuotaBytes) { continue }
            # The drive webUrl is the document library; the quota is set on its parent personal site.
            $SiteUrl = [string]$Drive.webUrl -replace '/[^/]+$', ''
            if ($SiteUrl -notmatch '/personal/') { continue }
            $Offenders.Add([PSCustomObject]@{
                    userPrincipalName = "$($User.userPrincipalName)"
                    currentQuotaGB    = [math]::Round([double]$Total / 1GB)
                    targetQuotaGB     = [math]::Round([double]$TargetQuotaBytes / 1GB)
                    siteUrl           = $SiteUrl
                })
        }
    } elseif ($EntitledById.Count -gt 0) {
        Write-Information "Baselines: OneDriveLicensedQuota on $TenantFilter has $($EntitledById.Count) users on a qualifying plan; Microsoft requires at least five before quotas above 1 TB are permitted."
    }

    @{
        Current = [PSCustomObject]@{
            offenders = @($Offenders.userPrincipalName | Sort-Object)
            targets   = @($Offenders)
        }
    }
}
