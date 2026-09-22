function Invoke-CIPPStandardOneDriveLicensedQuota {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) OneDriveLicensedQuota
    .SYNOPSIS
        (Label) Raise OneDrive storage quota for entitled users
    .DESCRIPTION
        (Helptext) Raises the OneDrive storage quota to 5 TB for users whose license includes that entitlement. Microsoft provisions every OneDrive at 1 TB and does not apply the licensed entitlement automatically. Users already at or above 5 TB, for example raised further by Microsoft support, are left untouched.
        (DocsDescription) Microsoft provisions every OneDrive with a 1 TB quota regardless of license. Users holding OneDrive for Business (Plan 2), SharePoint Online (Plan 2), or a bundle that includes one of these (Microsoft 365/Office 365 E3/E5, A3/A5, G3/G5) are entitled to 5 TB, but an admin has to raise the quota manually. This standard finds enabled users with a qualifying service plan whose OneDrive quota is below 5 TB and raises it to 5 TB, with the warning level at 90%. Users whose quota is already at or above 5 TB, for example increased to 25 TB by Microsoft support, are skipped. Microsoft only permits quotas above 1 TB when the subscription has five or more users on a qualifying plan, so tenants below that threshold are reported as compliant and left unchanged.
    .NOTES
        CAT
            SharePoint Standards
        TAG
        EXECUTIVETEXT
            Ensures employees receive the full OneDrive storage their licenses already include. Microsoft grants 5 TB of storage with most enterprise licenses but only provisions 1 TB by default, leaving paid-for capacity unused. Automatically correcting the allocation prevents storage shortages and support tickets without any additional licensing cost.
        ADDEDCOMPONENT
        IMPACT
            Low Impact
        ADDEDDATE
            2026-08-21
        POWERSHELLEQUIVALENT
            Set-SPOSite -Identity https://tenant-my.sharepoint.com/personal/user -StorageQuota 5242880
        RECOMMENDEDBY
        REQUIREDCAPABILITIES
            "SHAREPOINTENTERPRISE"
            "SHAREPOINTENTERPRISE_EDU"
            "SHAREPOINTENTERPRISE_GOV"
            "ONEDRIVEENTERPRISE"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'OneDriveLicensedQuota' -TenantFilter $Tenant -RequiredCapabilities @('SHAREPOINTENTERPRISE', 'SHAREPOINTENTERPRISE_EDU', 'SHAREPOINTENTERPRISE_GOV', 'ONEDRIVEENTERPRISE')

    if ($TestResult -eq $false) {
        return $true
    } #we're done.

    # Service plans that carry the 5 TB OneDrive entitlement (standalone Plan 2 SKUs and the
    # E3/E5-class bundles that include SharePoint Online Plan 2).
    $QualifyingPlanIds = @(
        '5dbe027f-2339-4123-9542-606e4d348a72' # SHAREPOINTENTERPRISE - SharePoint Online (Plan 2)
        '63038b2c-28d0-45f6-bc36-33062963b498' # SHAREPOINTENTERPRISE_EDU
        '153f85dd-d912-4762-af6c-d6e0fb4f6692' # SHAREPOINTENTERPRISE_GOV
        'afcafa6a-d966-4462-918c-ec0b4e0fe642' # ONEDRIVEENTERPRISE - OneDrive for Business (Plan 2)
    )
    $TargetQuotaBytes = 5TB
    $TargetQuotaMB = [int64](5TB / 1MB)
    $WarningLevelMB = [int64]($TargetQuotaMB * 0.9)

    try {
        $Users = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users?`$select=id,userPrincipalName,accountEnabled,assignedPlans&`$top=999&`$count=true" -tenantid $Tenant -ComplexFilter -AsApp $true
        $EntitledUsers = @($Users | Where-Object {
                $_.accountEnabled -eq $true -and
                ($_.assignedPlans | Where-Object { $_.capabilityStatus -eq 'Enabled' -and $_.servicePlanId -in $QualifyingPlanIds })
            })
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the OneDriveLicensedQuota state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    # Microsoft only allows OneDrive quotas above 1 TB when the subscription has five or more
    # users on a qualifying plan; below that the entitlement does not exist, so there is nothing
    # to remediate or alert on.
    $EntitlementApplies = $EntitledUsers.Count -ge 5
    if (-not $EntitlementApplies -and $EntitledUsers.Count -gt 0) {
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "OneDriveLicensedQuota: tenant has $($EntitledUsers.Count) users on a qualifying plan. Microsoft requires at least five before quotas above 1 TB are permitted, skipping." -sev Info
    }

    $BelowQuota = [System.Collections.Generic.List[object]]::new()
    if ($EntitlementApplies) {
        try {
            $DriveRequests = foreach ($User in $EntitledUsers) {
                @{
                    id     = $User.id
                    method = 'GET'
                    url    = "users/$($User.id)/drive?`$select=quota,webUrl"
                }
            }
            $DriveResponses = New-GraphBulkRequest -tenantid $Tenant -Requests @($DriveRequests) -asapp $true
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the OneDrive quotas for $Tenant. Error: $ErrorMessage" -Sev Error
            return
        }

        foreach ($Response in $DriveResponses) {
            # Non-200 means the user's OneDrive is not provisioned yet; it will pick up the
            # correct default when it is created.
            if ($Response.status -ne 200) { continue }
            $Quota = $Response.body.quota
            if (-not $Quota.total -or [int64]$Quota.total -le 0) { continue }
            # At or above the entitlement already, including quotas raised further by Microsoft
            # support (up to 25 TB) - never lower those.
            if ([int64]$Quota.total -ge $TargetQuotaBytes) { continue }

            # The drive webUrl points at the document library; its parent is the personal site
            # that the quota is set on.
            $SiteUrl = [string]$Response.body.webUrl -replace '/[^/]+$', ''
            if ($SiteUrl -notmatch '/personal/') { continue }

            $User = $EntitledUsers | Where-Object { $_.id -eq $Response.id } | Select-Object -First 1
            $BelowQuota.Add([PSCustomObject]@{
                    userPrincipalName = $User.userPrincipalName
                    currentQuotaGB    = [math]::Round([double]$Quota.total / 1GB)
                    targetQuotaGB     = [math]::Round([double]$TargetQuotaBytes / 1GB)
                    siteUrl           = $SiteUrl
                })
        }
    }

    if ($Settings.remediate -eq $true) {
        if ($BelowQuota.Count -eq 0) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All entitled users already have a OneDrive quota of 5 TB or more.' -sev Info
        } else {
            # One concurrent batch instead of ~2s per drive serially.
            $BulkSites = @($BelowQuota | ForEach-Object { @{ SiteUrl = $_.siteUrl; Properties = @{ StorageMaximumLevel = $TargetQuotaMB; StorageWarningLevel = $WarningLevelMB } } })
            $BulkResults = @(Set-CIPPSPOSiteBulk -TenantFilter $Tenant -Sites $BulkSites -UseCertificate)
            foreach ($Drive in $BelowQuota) {
                $BulkResult = $BulkResults | Where-Object { $_.SiteUrl -eq $Drive.siteUrl } | Select-Object -First 1
                if ($BulkResult -and $BulkResult.Success) {
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Raised OneDrive quota for $($Drive.userPrincipalName) from $($Drive.currentQuotaGB)GB to $($Drive.targetQuotaGB)GB" -sev Info
                } else {
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to raise OneDrive quota for $($Drive.userPrincipalName): $($BulkResult.Error)" -sev Error
                }
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($BelowQuota.Count -gt 0) {
            Write-StandardsAlert -message "OneDrive accounts below their licensed 5 TB quota: $($BelowQuota.Count)" -object $BelowQuota -tenant $Tenant -standardName 'OneDriveLicensedQuota' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "OneDrive accounts below their licensed 5 TB quota: $($BelowQuota.Count)" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'All entitled users already have a OneDrive quota of 5 TB or more.' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = [PSCustomObject]@{
            OneDriveBelowLicensedQuota = @($BelowQuota)
        }
        $ExpectedValue = [PSCustomObject]@{
            OneDriveBelowLicensedQuota = @()
        }

        Set-CIPPStandardsCompareField -FieldName 'standards.OneDriveLicensedQuota' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
        Add-CIPPBPAField -FieldName 'OneDriveLicensedQuota' -FieldValue @($BelowQuota) -StoreAs json -Tenant $Tenant
    }
}
