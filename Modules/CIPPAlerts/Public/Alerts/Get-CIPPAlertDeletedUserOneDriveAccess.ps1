function Get-CIPPAlertDeletedUserOneDriveAccess {
    <#
    .SYNOPSIS
        Alert on OneDrives of Entra-deleted users whose delegated access is about to end.

    .DESCRIPTION
        Watches the deleted-user OneDrive lifecycle rather than the unpaid-storage one that
        Get-CIPPAlertUnlicensedOneDriveData covers. When a user is deleted in Entra ID the
        tenant's OneDrive retention period starts (default 30 days). Whoever was given access
        to the OneDrive (manager, secondary owner, or the person picked during CIPP offboarding)
        can copy data out until the retention period ends and the site moves to the recycle bin.

        Microsoft also archives every unlicensed OneDrive on its 93rd unlicensed day unless
        unlicensed-account billing is enabled, so on tenants without billing the effective
        access window is the shorter of the retention period and 93 days.

        Data sources:
        - SPO admin aggregated-sites list, rows with UnlicensedOdbReason 2 (owner deleted)
        - Graph beta admin/sharepoint/settings for deletedUserPersonalSiteRetentionPeriodInDays
        - SPO admin tenant billing flag (UnlicensedOdbSyntexBillingEnabled)
        - Per-site siteusers (IsSiteAdmin) for the people who currently hold delegated access

        Items carry UserPrincipalName (the deleted owner) so the lifecycle hash stays stable
        across runs while the day count changes.

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    $HasSharePoint = Test-CIPPStandardLicense -StandardName 'DeletedUserOneDriveAccess' -TenantFilter $TenantFilter -Preset SharePoint
    if (-not $HasSharePoint) {
        return
    }

    if ($InputValue -is [string]) {
        try {
            if ($InputValue.Trim().StartsWith('{')) {
                $InputValue = $InputValue | ConvertFrom-Json -ErrorAction Stop
            }
        } catch {
            # Leave as-is if parsing fails
        }
    }

    $DaysThreshold = 14
    $RequireDelegate = $false
    if ($InputValue -is [hashtable] -or $InputValue -is [PSCustomObject]) {
        $DaysRaw = $InputValue.DeletedUserOneDriveAccess
        if ($null -ne $DaysRaw -and "$DaysRaw" -ne '') {
            $ParsedDays = 0
            if ([int]::TryParse("$DaysRaw", [ref]$ParsedDays) -and $ParsedDays -ge 1) {
                $DaysThreshold = $ParsedDays
            }
        }
        if ($null -ne $InputValue.RequireDelegate) {
            $RequireDelegate = [bool]$InputValue.RequireDelegate
        }
    } elseif ($null -ne $InputValue -and "$InputValue" -ne '') {
        $ParsedDays = 0
        if ([int]::TryParse("$InputValue", [ref]$ParsedDays) -and $ParsedDays -ge 1) {
            $DaysThreshold = $ParsedDays
        }
    }

    try {
        $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
        $AdminUrl = $SharePointInfo.AdminUrl.TrimEnd('/')
    } catch {
        return
    }

    # Retention period for deleted users' OneDrives. Same endpoint the DeletedUserRentention
    # standard reads. Microsoft's default is 30 days when the call fails.
    $RetentionDays = 30
    try {
        $SpoSettings = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -tenantid $TenantFilter -AsApp $true
        $ParsedRetention = 0
        if ([int]::TryParse("$($SpoSettings.deletedUserPersonalSiteRetentionPeriodInDays)", [ref]$ParsedRetention) -and $ParsedRetention -ge 1) {
            $RetentionDays = $ParsedRetention
        }
    } catch {
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "DeletedUserOneDriveAccess: could not read the OneDrive retention period, assuming 30 days. $($_.Exception.Message)" -sev Debug
    }

    # Unlicensed-account billing keeps archived OneDrives reachable; without it the site is
    # archived on day 93 regardless of the retention period. Assume no billing when unknown.
    $BillingEnabled = $false
    try {
        $extraHeaders = @{ 'Accept' = 'application/json' }
        $Billing = New-GraphGetRequest -extraHeaders $extraHeaders -scope "$AdminUrl/.default" -tenantid $TenantFilter -uri "$AdminUrl/_api/SPOInternalUseOnly.Tenant/?`$select=UnlicensedOdbSyntexBillingEnabled" -AsApp $true -UseCertificate
        $BillingEnabled = $Billing.UnlicensedOdbSyntexBillingEnabled -eq $true
    } catch {
        $BillingEnabled = $false
    }

    # Personal sites whose owner was deleted from Entra ID (UnlicensedOdbReason 2) and that
    # have not been deleted themselves yet.
    $ViewXml = @'
<View><Query><Where><And><And><Eq><FieldRef Name="UnlicensedOdbReason"/><Value Type="Integer">2</Value></Eq><Eq><FieldRef Name="TemplateId"/><Value Type="Integer">21</Value></Eq></And><And><IsNull><FieldRef Name="TimeDeleted"/></IsNull><And><Neq><FieldRef Name="TemplateName"/><Value Type="Text">TEAMCHANNEL#0</Value></Neq><Neq><FieldRef Name="TemplateName"/><Value Type="Text">TEAMCHANNEL#1</Value></Neq></And></And></And></Where></Query><ViewFields><FieldRef Name="Title"/><FieldRef Name="SiteUrl"/><FieldRef Name="SiteOwnerEmail"/><FieldRef Name="UnlicensedOdbProvisionedForUPN"/><FieldRef Name="UnlicensedOdbStartDate"/><FieldRef Name="ArchiveStatus"/><FieldRef Name="StorageUsed"/><FieldRef Name="UnlicensedOdbReason"/><FieldRef Name="UnlicensedOdbCleanupBlockReason"/><FieldRef Name="UnlicensedOdbInfoLastRefreshOn"/></ViewFields><RowLimit Paged="TRUE">200</RowLimit></View>
'@

    try {
        $Rows = @(Get-CIPPSPOAdminListData -TenantFilter $TenantFilter -AdminUrl $AdminUrl -ListName 'DO_NOT_DELETE_SPLIST_TENANTADMIN_ALL_SITES_AGGREGATED_SITECOLLECTIONS' -ViewXml $ViewXml)
    } catch {
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "DeletedUserOneDriveAccess: could not read the SharePoint admin site list. $($_.Exception.Message)" -sev Debug
        return
    }

    $Today = (Get-Date).Date
    $AlertData = foreach ($Row in $Rows) {
        $StartRaw = [string]$Row.UnlicensedOdbStartDate
        if ([string]::IsNullOrWhiteSpace($StartRaw)) {
            continue
        }
        $DeletedOn = [datetime]::MinValue
        if (-not [datetime]::TryParse($StartRaw, [ref]$DeletedOn)) {
            continue
        }
        $DeletedOn = $DeletedOn.Date

        $EstimatedDeletionOn = $DeletedOn.AddDays($RetentionDays)
        $ArchiveOn = $DeletedOn.AddDays(93)
        $AccessEndsOn = $EstimatedDeletionOn
        $AccessEndReason = 'retention period ends'
        if (-not $BillingEnabled -and $ArchiveOn -lt $EstimatedDeletionOn) {
            $AccessEndsOn = $ArchiveOn
            $AccessEndReason = 'site is archived on its 93rd unlicensed day'
        }

        $DaysUntilAccessEnds = [int][math]::Floor(($AccessEndsOn - $Today).TotalDays)
        if ($DaysUntilAccessEnds -lt 0 -or $DaysUntilAccessEnds -gt $DaysThreshold) {
            continue
        }

        $OwnerUpn = [string]$Row.UnlicensedOdbProvisionedForUPN
        if ([string]::IsNullOrWhiteSpace($OwnerUpn)) {
            $OwnerUpn = [string]$Row.SiteOwnerEmail
        }
        $SiteUrl = [string]$Row.SiteUrl
        if ([string]::IsNullOrWhiteSpace($SiteUrl)) {
            continue
        }

        # Who currently holds delegated access: site collection admins other than the deleted
        # owner. Same call the site members endpoint and the root-permissions cache use.
        $DelegateLookupOk = $false
        $Delegates = [System.Collections.Generic.List[string]]::new()
        try {
            $RestContext = Resolve-CIPPSharePointRestContext -TenantFilter $TenantFilter -SiteUrl $SiteUrl -SharePointInfo $SharePointInfo
            $Admins = @(New-GraphGetRequest -uri "$($RestContext.BaseUri)/web/siteusers?`$filter=IsSiteAdmin eq true&`$select=Id,Title,Email,LoginName,PrincipalType" -tenantid $TenantFilter -scope $RestContext.Scope -extraHeaders $RestContext.Headers -UseCertificate -AsApp $true)
            foreach ($Admin in $Admins) {
                if ($Admin.PrincipalType -ne 1) {
                    continue
                }
                $AdminUpn = ([string]$Admin.LoginName -split '\|')[-1]
                if ([string]::IsNullOrWhiteSpace($AdminUpn) -or $AdminUpn -like 'SHAREPOINT\*' -or $AdminUpn -like 'app@sharepoint') {
                    continue
                }
                if (-not [string]::IsNullOrWhiteSpace($OwnerUpn) -and $AdminUpn -ieq $OwnerUpn) {
                    continue
                }
                if (-not $Delegates.Contains($AdminUpn)) {
                    $Delegates.Add($AdminUpn)
                }
            }
            $DelegateLookupOk = $true
        } catch {
            $DelegateLookupOk = $false
        }

        if ($RequireDelegate -and $DelegateLookupOk -and $Delegates.Count -eq 0) {
            continue
        }

        $StorageUsedGB = $null
        if ($null -ne $Row.StorageUsed) {
            $StorageUsedGB = [math]::Round([double]$Row.StorageUsed / 1GB, 2)
        }

        $Title = [string]$Row.Title
        if ([string]::IsNullOrWhiteSpace($Title)) {
            $Title = $OwnerUpn
        }
        $Identity = if (-not [string]::IsNullOrWhiteSpace($OwnerUpn)) { "$Title ($OwnerUpn)" } else { $Title }
        $DelegateNote = if (-not $DelegateLookupOk) {
            ' Could not determine who holds delegated access.'
        } elseif ($Delegates.Count -eq 0) {
            ' Nobody holds delegated access.'
        } else {
            " Delegated access held by: $($Delegates -join ', ')."
        }
        $Message = "OneDrive of deleted user $Identity loses access in $DaysUntilAccessEnds days on $($AccessEndsOn.ToString('yyyy-MM-dd')) ($AccessEndReason). User deleted on $($DeletedOn.ToString('yyyy-MM-dd')), retention period $RetentionDays days, estimated deletion $($EstimatedDeletionOn.ToString('yyyy-MM-dd')).$DelegateNote"

        $Item = [PSCustomObject]@{
            Message                         = $Message
            UserPrincipalName               = $OwnerUpn
            Title                           = $Title
            SiteUrl                         = $SiteUrl
            DeletedOn                       = $DeletedOn
            RetentionPeriodDays             = $RetentionDays
            EstimatedDeletionOn             = $EstimatedDeletionOn
            AccessEndsOn                    = $AccessEndsOn
            AccessEndReason                 = $AccessEndReason
            DaysUntilAccessEnds             = $DaysUntilAccessEnds
            UnlicensedBillingEnabled        = $BillingEnabled
            ArchiveStatus                   = [string]$Row.ArchiveStatus
            StorageUsedGB                   = $StorageUsedGB
            UnlicensedOdbCleanupBlockReason = $Row.UnlicensedOdbCleanupBlockReason
            Tenant                          = $TenantFilter
        }
        if ($DelegateLookupOk) {
            $Item | Add-Member -NotePropertyName 'Delegates' -NotePropertyValue @($Delegates)
        }
        $Item
    }

    Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
}
