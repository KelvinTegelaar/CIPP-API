function Invoke-ExecSiteBrowserActions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
    .DESCRIPTION
        Mutating / operational actions for the SharePoint site browser (non-permissions).
        Body.Action selects the operation. SiteUrl + tenantFilter are always required.
        Version cleanup: StartVersionCleanup, GetVersionCleanupStatus.
        Site admin properties (incl. version policy): GetSiteProperties.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter ?? $Request.Body.TenantFilter
    $SiteUrl = $Request.Body.SiteUrl
    $SiteId = $Request.Body.SiteId
    $Action = $Request.Body.Action

    try {
        if ([string]::IsNullOrWhiteSpace($TenantFilter)) { throw 'tenantFilter is required.' }
        if ([string]::IsNullOrWhiteSpace($Action)) { throw 'Action is required.' }
        if ([string]::IsNullOrWhiteSpace($SiteUrl) -and [string]::IsNullOrWhiteSpace($SiteId)) {
            throw 'SiteUrl or SiteId is required.'
        }

        if (-not [string]::IsNullOrWhiteSpace($SiteUrl)) {
            $ResolvedUrl = $SiteUrl.TrimEnd('/')
        } else {
            $SiteMeta = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/sites/$SiteId`?`$select=webUrl" -tenantid $TenantFilter -asapp $true
            if ([string]::IsNullOrWhiteSpace($SiteMeta.webUrl)) {
                throw "Could not resolve webUrl for site id $SiteId."
            }
            $ResolvedUrl = $SiteMeta.webUrl.TrimEnd('/')
        }

        $Result = switch ([string]$Action) {
            'StartVersionCleanup' {
                $BatchDeleteMode = [int]($Request.Body.BatchDeleteMode ?? 2)
                if ($Request.Body.BatchDeleteMode -is [PSCustomObject] -and $Request.Body.BatchDeleteMode.value) {
                    $BatchDeleteMode = [int]$Request.Body.BatchDeleteMode.value
                }

                $DeleteOlderThanDays = [int]($Request.Body.DeleteOlderThanDays ?? -1)
                $MajorVersionLimit = [int]($Request.Body.MajorVersionLimit ?? -1)
                $MajorWithMinorVersionsLimit = [int]($Request.Body.MajorWithMinorVersionsLimit ?? -1)
                $SyncListPolicy = $Request.Body.SyncListPolicy -eq $true

                switch ($BatchDeleteMode) {
                    0 {
                        if ($DeleteOlderThanDays -lt 30) {
                            throw 'DeleteOlderThanDays must be at least 30 when using Delete Older Than Days mode.'
                        }
                        $MajorVersionLimit = -1
                        $MajorWithMinorVersionsLimit = -1
                    }
                    1 {
                        if ($MajorVersionLimit -lt 1) {
                            throw 'MajorVersionLimit is required when using Count Limits mode.'
                        }
                        if ($MajorWithMinorVersionsLimit -lt 0) {
                            throw 'MajorWithMinorVersionsLimit is required when using Count Limits mode.'
                        }
                        $DeleteOlderThanDays = -1
                    }
                    2 {
                        $DeleteOlderThanDays = -1
                        $MajorVersionLimit = -1
                        $MajorWithMinorVersionsLimit = -1
                    }
                    default {
                        throw "Unsupported BatchDeleteMode '$BatchDeleteMode'. Use 0 (DeleteOlderThanDays), 1 (CountLimits), or 2 (SyncPolicy)."
                    }
                }

                $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
                $AdminUrl = $SharePointInfo.AdminUrl
                $EscapedSiteUrl = [System.Security.SecurityElement]::Escape($ResolvedUrl)
                $SyncListPolicyValue = $SyncListPolicy.ToString().ToLower()

                $XML = @"
<Request AddExpandoFieldTypeSuffix="true" SchemaVersion="15.0.0.0" LibraryVersion="16.0.0.0" ApplicationName="SharePoint Online PowerShell (16.0.24908.0)" xmlns="http://schemas.microsoft.com/sharepoint/clientquery/2009"><Actions><ObjectPath Id="199" ObjectPathId="198" /><ObjectPath Id="201" ObjectPathId="200" /><Query Id="202" ObjectPathId="200"><Query SelectAllProperties="true"><Properties /></Query></Query></Actions><ObjectPaths><Constructor Id="198" TypeId="{268004ae-ef6b-4e9b-8425-127220d84719}" /><Method Id="200" ParentId="198" Name="NewFileVersionBatchDeleteJob"><Parameters><Parameter Type="String">$EscapedSiteUrl</Parameter><Parameter TypeId="{d1fd43d3-dba9-4d1c-bf13-d3894db255c7}"><Property Name="BatchDeleteMode" Type="Enum">$BatchDeleteMode</Property><Property Name="DeleteOlderThanDays" Type="Int32">$DeleteOlderThanDays</Property><Property Name="FileTypeSelections" Type="Null" /><Property Name="MajorVersionLimit" Type="Int32">$MajorVersionLimit</Property><Property Name="MajorWithMinorVersionsLimit" Type="Int32">$MajorWithMinorVersionsLimit</Property><Property Name="SyncListPolicy" Type="Boolean">$SyncListPolicyValue</Property></Parameter></Parameters></Method></ObjectPaths></Request>
"@

                $AdditionalHeaders = @{
                    'Accept' = 'application/json;odata=verbose'
                }
                $Response = New-GraphPostRequest -scope "$AdminUrl/.default" -tenantid $TenantFilter -Uri "$AdminUrl/_vti_bin/client.svc/ProcessQuery" -Type POST -Body $XML -ContentType 'text/xml' -AddedHeaders $AdditionalHeaders

                if ($Response -is [string]) {
                    $Response = $Response | ConvertFrom-Json
                }
                $ErrorInfo = $Response | Where-Object { $_.PSObject.Properties.Name -contains 'ErrorInfo' } | Select-Object -First 1
                if ($ErrorInfo.ErrorInfo) {
                    throw "SharePoint rejected the version cleanup job for $ResolvedUrl : $($ErrorInfo.ErrorInfo.ErrorMessage)"
                }

                "Successfully started version cleanup job for $ResolvedUrl."
            }
            'GetVersionCleanupStatus' {
                $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
                $AdminUrl = $SharePointInfo.AdminUrl
                $EscapedSiteUrl = [System.Security.SecurityElement]::Escape($ResolvedUrl)

                $XML = @"
<Request AddExpandoFieldTypeSuffix="true" SchemaVersion="15.0.0.0" LibraryVersion="16.0.0.0" ApplicationName="SharePoint Online PowerShell (16.0.24908.0)" xmlns="http://schemas.microsoft.com/sharepoint/clientquery/2009"><Actions><ObjectPath Id="40" ObjectPathId="39" /><Method Name="GetFileVersionBatchDeleteJobProgress" Id="41" ObjectPathId="39"><Parameters><Parameter Type="String">$EscapedSiteUrl</Parameter></Parameters></Method></Actions><ObjectPaths><Constructor Id="39" TypeId="{268004ae-ef6b-4e9b-8425-127220d84719}" /></ObjectPaths></Request>
"@

                $AdditionalHeaders = @{
                    'Accept' = 'application/json;odata=verbose'
                }
                $Response = New-GraphPostRequest -scope "$AdminUrl/.default" -tenantid $TenantFilter -Uri "$AdminUrl/_vti_bin/client.svc/ProcessQuery" -Type POST -Body $XML -ContentType 'text/xml' -AddedHeaders $AdditionalHeaders

                if ($Response -is [string]) {
                    $Response = $Response | ConvertFrom-Json
                }

                $ErrorInfo = $Response | Where-Object { $_.PSObject.Properties.Name -contains 'ErrorInfo' } | Select-Object -First 1
                if ($ErrorInfo.ErrorInfo) {
                    throw "SharePoint returned an error querying version cleanup status for $ResolvedUrl : $($ErrorInfo.ErrorInfo.ErrorMessage)"
                }

                $ProgressJson = $Response | Where-Object { $_ -is [string] } | Select-Object -First 1
                if ([string]::IsNullOrWhiteSpace($ProgressJson)) {
                    [PSCustomObject]@{
                        SiteUrl = $ResolvedUrl
                        Status  = 'NoRequestFound'
                        Message = 'No file version batch delete job found for this site.'
                    }
                } else {
                    $Progress = $ProgressJson | ConvertFrom-Json
                    if ($Progress -isnot [PSCustomObject]) {
                        $Progress = [PSCustomObject]$Progress
                    }
                    $Progress | Add-Member -NotePropertyName SiteUrl -NotePropertyValue $ResolvedUrl -Force
                    $Progress
                }
            }
            'GetSiteProperties' {
                $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
                $AdminUrl = $SharePointInfo.AdminUrl
                $EscapedSiteUrl = [System.Security.SecurityElement]::Escape($ResolvedUrl)

                $XML = @"
<Request AddExpandoFieldTypeSuffix="true" SchemaVersion="15.0.0.0" LibraryVersion="16.0.0.0" ApplicationName="SharePoint Online PowerShell (16.0.24908.0)" xmlns="http://schemas.microsoft.com/sharepoint/clientquery/2009"><Actions><ObjectPath Id="2" ObjectPathId="1" /><ObjectPath Id="4" ObjectPathId="3" /><Query Id="5" ObjectPathId="3"><Query SelectAllProperties="true"><Properties /></Query></Query></Actions><ObjectPaths><Constructor Id="1" TypeId="{268004ae-ef6b-4e9b-8425-127220d84719}" /><Method Id="3" ParentId="1" Name="GetSitePropertiesByUrl"><Parameters><Parameter Type="String">$EscapedSiteUrl</Parameter><Parameter Type="Boolean">true</Parameter></Parameters></Method></ObjectPaths></Request>
"@

                $AdditionalHeaders = @{ 'Accept' = 'application/json;odata=verbose' }
                $Response = New-GraphPostRequest -scope "$AdminUrl/.default" -tenantid $TenantFilter -Uri "$AdminUrl/_vti_bin/client.svc/ProcessQuery" -Type POST -Body $XML -ContentType 'text/xml' -AddedHeaders $AdditionalHeaders

                if ($Response -is [string]) {
                    $Response = $Response | ConvertFrom-Json
                }

                $ErrorInfo = $Response | Where-Object { $_.PSObject.Properties.Name -contains 'ErrorInfo' } | Select-Object -First 1
                if ($ErrorInfo.ErrorInfo) {
                    throw "SharePoint returned an error reading site properties for $ResolvedUrl : $($ErrorInfo.ErrorInfo.ErrorMessage)"
                }

                $Site = $Response | Where-Object { $_._ObjectType_ -match 'SiteProperties' } | Select-Object -First 1
                if (-not $Site) {
                    throw "Could not retrieve site properties for $ResolvedUrl"
                }

                $SharingCapabilityNames = @{ 0 = 'Disabled'; 1 = 'ExternalUserSharingOnly'; 2 = 'ExternalUserAndGuestSharing'; 3 = 'ExistingExternalUserSharingOnly' }
                $LinkTypeNames = @{ 0 = 'None'; 1 = 'Direct'; 2 = 'Internal'; 3 = 'AnonymousAccess' }
                $LinkPermissionNames = @{ 0 = 'None'; 1 = 'View'; 2 = 'Edit' }
                $DomainRestrictionNames = @{ 0 = 'None'; 1 = 'AllowList'; 2 = 'BlockList' }

                [PSCustomObject]@{
                    Url                                         = $Site.Url ?? $ResolvedUrl
                    Title                                       = $Site.Title
                    Template                                    = $Site.Template
                    SharingCapability                           = $SharingCapabilityNames[[int]$Site.SharingCapability] ?? $Site.SharingCapability
                    DefaultSharingLinkType                      = $LinkTypeNames[[int]$Site.DefaultSharingLinkType] ?? $Site.DefaultSharingLinkType
                    DefaultLinkPermission                       = $LinkPermissionNames[[int]$Site.DefaultLinkPermission] ?? $Site.DefaultLinkPermission
                    SharingDomainRestrictionMode                = $DomainRestrictionNames[[int]$Site.SharingDomainRestrictionMode] ?? $Site.SharingDomainRestrictionMode
                    SharingAllowedDomainList                    = $Site.SharingAllowedDomainList
                    SharingBlockedDomainList                    = $Site.SharingBlockedDomainList
                    OverrideTenantAnonymousLinkExpirationPolicy = [bool]$Site.OverrideTenantAnonymousLinkExpirationPolicy
                    AnonymousLinkExpirationInDays               = $Site.AnonymousLinkExpirationInDays
                    LockState                                   = $Site.LockState
                    StorageMaximumLevel                         = $Site.StorageMaximumLevel
                    StorageWarningLevel                         = $Site.StorageWarningLevel
                    StorageUsage                                = $Site.StorageUsage
                    InheritVersionPolicyFromTenant              = [bool]$Site.InheritVersionPolicyFromTenant
                    EnableAutoExpirationVersionTrim             = [bool]$Site.EnableAutoExpirationVersionTrim
                    MajorVersionLimit                           = $Site.MajorVersionLimit
                    ExpireVersionsAfterDays                     = $Site.ExpireVersionsAfterDays
                }
            }
            default {
                throw "Unknown Action '$Action'. Supported: StartVersionCleanup, GetVersionCleanupStatus, GetSiteProperties."
            }
        }

        if ($Result -is [string]) {
            Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Info
        } elseif ($Action -eq 'GetSiteProperties') {
            Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Retrieved site properties for $($Result.Url ?? $ResolvedUrl)" -sev Info
        } else {
            Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Retrieved version cleanup status for $($Result.SiteUrl ?? $ResolvedUrl)" -sev Info
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to run Action '$Action'. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })
}
