function Get-CIPPAlertUnlicensedOneDriveData {
    <#
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

    $HasSharePoint = Test-CIPPStandardLicense -StandardName 'UnlicensedOneDriveData' -TenantFilter $TenantFilter -Preset SharePoint
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

    $DaysThreshold = 30
    $IncludeSharedMailboxes = $false
    if ($InputValue -is [hashtable] -or $InputValue -is [PSCustomObject]) {
        $DaysRaw = $InputValue.UnlicensedOneDriveData
        if ($null -ne $DaysRaw -and "$DaysRaw" -ne '') {
            $ParsedDays = 0
            if ([int]::TryParse("$DaysRaw", [ref]$ParsedDays) -and $ParsedDays -ge 1) {
                $DaysThreshold = $ParsedDays
            }
        }
        if ($null -ne $InputValue.IncludeSharedMailboxes) {
            $IncludeSharedMailboxes = [bool]$InputValue.IncludeSharedMailboxes
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
        $extraHeaders = @{
            'Accept' = 'application/json'
        }
        $Billing = New-GraphGetRequest -extraHeaders $extraHeaders -scope "$AdminUrl/.default" -tenantid $TenantFilter -uri "$AdminUrl/_api/SPOInternalUseOnly.Tenant/?`$select=UnlicensedOdbSyntexBillingEnabled,UnlicensedOdbStorageBillingMode" -AsApp $true -UseCertificate
    } catch {
        return
    }

    if ($Billing.UnlicensedOdbSyntexBillingEnabled -eq $true) {
        return
    }

    $ViewXml = @'
<View><Query><Where><And><And><And><And><IsNotNull><FieldRef Name="UnlicensedOdbReason"/></IsNotNull><Neq><FieldRef Name="UnlicensedOdbReason"/><Value Type="Integer">0</Value></Neq></And><IsNotNull><FieldRef Name="UnlicensedOdbCleanupBlockReason"/></IsNotNull></And><And><Eq><FieldRef Name="TemplateId"/><Value Type="Integer">21</Value></Eq><IsNull><FieldRef Name="TimeDeleted"/></IsNull></And></And><And><Neq><FieldRef Name="TemplateName"/><Value Type="Text">TEAMCHANNEL#0</Value></Neq><Neq><FieldRef Name="TemplateName"/><Value Type="Text">TEAMCHANNEL#1</Value></Neq></And></And></Where></Query><ViewFields><FieldRef Name="Title"/><FieldRef Name="SiteUrl"/><FieldRef Name="SiteOwnerEmail"/><FieldRef Name="UnlicensedOdbProvisionedForUPN"/><FieldRef Name="UnlicensedOdbStartDate"/><FieldRef Name="ArchiveStatus"/><FieldRef Name="StorageUsed"/><FieldRef Name="UnlicensedOdbReason"/><FieldRef Name="UnlicensedOdbCleanupBlockReason"/><FieldRef Name="UnlicensedOdbInfoLastRefreshOn"/></ViewFields><RowLimit Paged="TRUE">200</RowLimit></View>
'@

    try {
        $Rows = @(Get-CIPPSPOAdminListData -TenantFilter $TenantFilter -AdminUrl $AdminUrl -ListName 'DO_NOT_DELETE_SPLIST_TENANTADMIN_ALL_SITES_AGGREGATED_SITECOLLECTIONS' -ViewXml $ViewXml)
    } catch {
        return
    }

    $SharedLookupOk = $false
    $SharedUpns = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    try {
        $SharedMailboxes = @(New-GraphGetRequest -uri "https://outlook.office365.com/adminapi/beta/$TenantFilter/Mailbox?`$filter=RecipientTypeDetails eq 'SharedMailbox'" -Tenantid $TenantFilter -scope ExchangeOnline)
        foreach ($Mailbox in $SharedMailboxes) {
            $SharedUpn = [string]$Mailbox.UserPrincipalName
            if ([string]::IsNullOrWhiteSpace($SharedUpn)) {
                $SharedUpn = [string]$Mailbox.userPrincipalName
            }
            if (-not [string]::IsNullOrWhiteSpace($SharedUpn)) {
                [void]$SharedUpns.Add($SharedUpn)
            }
        }
        $SharedLookupOk = $true
    } catch {
        $SharedLookupOk = $false
    }

    $Today = (Get-Date).Date
    $AlertData = foreach ($Row in $Rows) {
        $ReasonInt = 0
        if (-not [int]::TryParse("$($Row.UnlicensedOdbReason)", [ref]$ReasonInt)) {
            $ReasonInt = -1
        }
        if ($ReasonInt -eq 2) {
            continue
        }

        $StartRaw = [string]$Row.UnlicensedOdbStartDate
        if ([string]::IsNullOrWhiteSpace($StartRaw)) {
            continue
        }
        $StartDate = [datetime]::MinValue
        if (-not [datetime]::TryParse($StartRaw, [ref]$StartDate)) {
            continue
        }

        $EstimatedDeletionOn = $StartDate.AddDays(365).Date
        $DaysUntilDeletion = [int][math]::Floor(($EstimatedDeletionOn - $Today).TotalDays)
        if ($DaysUntilDeletion -lt 0 -or $DaysUntilDeletion -gt $DaysThreshold) {
            continue
        }

        $Upn = [string]$Row.UnlicensedOdbProvisionedForUPN
        if ([string]::IsNullOrWhiteSpace($Upn)) {
            $Upn = [string]$Row.SiteOwnerEmail
        }

        $IsSharedMailbox = $false
        if ($SharedLookupOk -and -not [string]::IsNullOrWhiteSpace($Upn)) {
            $IsSharedMailbox = $SharedUpns.Contains($Upn)
        }
        if (-not $IncludeSharedMailboxes -and $IsSharedMailbox) {
            continue
        }

        $StorageUsedGB = $null
        if ($null -ne $Row.StorageUsed) {
            $StorageUsedGB = [math]::Round([double]$Row.StorageUsed / 1GB, 2)
        }

        $Title = [string]$Row.Title
        if ([string]::IsNullOrWhiteSpace($Title)) {
            $Title = $Upn
        }
        $Identity = if (-not [string]::IsNullOrWhiteSpace($Upn)) { "$Title ($Upn)" } else { $Title }
        $SharedNote = if ($SharedLookupOk -and $IsSharedMailbox) { ' Shared mailbox.' } else { '' }
        $Message = "$Identity unlicensed OneDrive data estimated to be deleted in $DaysUntilDeletion days (unlicensed since $($StartDate.ToString('yyyy-MM-dd'))).$SharedNote"

        $Item = [PSCustomObject]@{
            Message                          = $Message
            UnlicensedOdbProvisionedForUPN   = [string]$Row.UnlicensedOdbProvisionedForUPN
            SiteOwnerEmail                   = [string]$Row.SiteOwnerEmail
            Title                            = $Title
            SiteUrl                          = [string]$Row.SiteUrl
            UnlicensedOdbStartDate           = $StartDate
            EstimatedDeletionOn              = $EstimatedDeletionOn
            DaysUntilDeletion                = $DaysUntilDeletion
            ArchiveStatus                    = [string]$Row.ArchiveStatus
            StorageUsedGB                    = $StorageUsedGB
            UnlicensedOdbReason              = $Row.UnlicensedOdbReason
            UnlicensedOdbCleanupBlockReason  = $Row.UnlicensedOdbCleanupBlockReason
            Tenant                           = $TenantFilter
        }
        if ($SharedLookupOk) {
            $Item | Add-Member -NotePropertyName 'IsSharedMailbox' -NotePropertyValue $IsSharedMailbox
        }
        $Item
    }

    if ($AlertData) {
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
    }
}
