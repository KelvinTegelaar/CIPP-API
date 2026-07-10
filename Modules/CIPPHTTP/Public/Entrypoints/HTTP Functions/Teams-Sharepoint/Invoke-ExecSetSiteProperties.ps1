function Invoke-ExecSetSiteProperties {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
    .DESCRIPTION
        Sets admin-level properties on a single SharePoint site (sharing, lifecycle, version
        policy) through Set-CIPPSPOSite. Only whitelisted properties are accepted; enum values
        arrive as friendly names (matching Invoke-ListSiteProperties output) and are converted
        to their numeric CSOM values here.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $SiteUrl = $Request.Body.SiteUrl

    # Friendly name -> SPO enum value maps
    $EnumMaps = @{
        SharingCapability            = @{ 'Disabled' = 0; 'ExternalUserSharingOnly' = 1; 'ExternalUserAndGuestSharing' = 2; 'ExistingExternalUserSharingOnly' = 3 }
        DefaultSharingLinkType       = @{ 'None' = 0; 'Direct' = 1; 'Internal' = 2; 'AnonymousAccess' = 3 }
        DefaultLinkPermission        = @{ 'None' = 0; 'View' = 1; 'Edit' = 2 }
        SharingDomainRestrictionMode = @{ 'None' = 0; 'AllowList' = 1; 'BlockList' = 2 }
    }
    $StringProperties = @('Title', 'SharingAllowedDomainList', 'SharingBlockedDomainList')
    $BoolProperties = @('OverrideTenantAnonymousLinkExpirationPolicy', 'InheritVersionPolicyFromTenant', 'EnableAutoExpirationVersionTrim', 'ApplyToNewDocumentLibraries', 'ApplyToExistingDocumentLibraries')
    $IntProperties = @('AnonymousLinkExpirationInDays', 'MajorVersionLimit', 'ExpireVersionsAfterDays')
    $Int64Properties = @('StorageMaximumLevel', 'StorageWarningLevel')
    $ValidLockStates = @('Unlock', 'ReadOnly', 'NoAccess')

    try {
        if (-not $SiteUrl) { throw 'SiteUrl is required.' }

        $Properties = @{}
        $Changes = [System.Collections.Generic.List[string]]::new()

        foreach ($Key in $EnumMaps.Keys) {
            $Value = $Request.Body.$Key.value ?? $Request.Body.$Key
            if ($null -ne $Value -and "$Value" -ne '') {
                if (-not $EnumMaps[$Key].ContainsKey([string]$Value)) {
                    throw "Invalid value '$Value' for $Key. Valid values: $($EnumMaps[$Key].Keys -join ', ')."
                }
                $Properties[$Key] = [int]$EnumMaps[$Key][[string]$Value]
                $Changes.Add("$Key=$Value")
            }
        }

        $LockState = $Request.Body.LockState.value ?? $Request.Body.LockState
        if ($null -ne $LockState -and "$LockState" -ne '') {
            if ($LockState -notin $ValidLockStates) {
                throw "Invalid LockState '$LockState'. Valid values: $($ValidLockStates -join ', ')."
            }
            $Properties['LockState'] = [string]$LockState
            $Changes.Add("LockState=$LockState")
        }

        foreach ($Key in $StringProperties) {
            $Value = $Request.Body.$Key
            if ($null -ne $Value) {
                $Properties[$Key] = [string]$Value
                $Changes.Add("$Key=$Value")
            }
        }
        foreach ($Key in $BoolProperties) {
            $Value = $Request.Body.$Key
            if ($null -ne $Value) {
                $Properties[$Key] = [bool]$Value
                $Changes.Add("$Key=$Value")
            }
        }
        foreach ($Key in $IntProperties) {
            $Value = $Request.Body.$Key
            if ($null -ne $Value -and "$Value" -ne '') {
                $Properties[$Key] = [int]$Value
                $Changes.Add("$Key=$Value")
            }
        }
        foreach ($Key in $Int64Properties) {
            $Value = $Request.Body.$Key
            if ($null -ne $Value -and "$Value" -ne '') {
                $Properties[$Key] = [int64]$Value
                $Changes.Add("$Key=$Value")
            }
        }

        if ($Properties.Count -eq 0) {
            throw 'No valid properties were provided to set.'
        }

        # Group-connected sites only accept a small subset of tenant site properties; SPO
        # rejects the whole request if any other property is included. Filter to the
        # supported set and report what was skipped.
        $Site = Get-CIPPSPOSite -TenantFilter $TenantFilter -SiteUrl $SiteUrl
        $IsGroupSite = $Site.GroupId -and $Site.GroupId -notmatch '^0{8}-'
        $Skipped = [System.Collections.Generic.List[string]]::new()
        if ($IsGroupSite) {
            $GroupSiteAllowed = @('SharingCapability', 'DefaultSharingLinkType', 'DefaultLinkPermission', 'LockState', 'StorageMaximumLevel', 'StorageWarningLevel')
            foreach ($Key in @($Properties.Keys)) {
                if ($Key -notin $GroupSiteAllowed) {
                    $Properties.Remove($Key)
                    $Skipped.Add($Key)
                }
            }
            if ($Properties.Count -eq 0) {
                throw "None of the selected properties can be changed on a group-connected site. Supported: $($GroupSiteAllowed -join ', ')."
            }
        }

        $Response = Set-CIPPSPOSite -TenantFilter $TenantFilter -SiteUrl $SiteUrl -Properties $Properties
        $CsomError = ($Response | Where-Object { $_.ErrorInfo } | Select-Object -First 1).ErrorInfo.ErrorMessage
        if ($CsomError) {
            throw $CsomError
        }

        $AppliedChanges = $Changes | Where-Object { ($_ -split '=')[0] -in $Properties.Keys }
        $Results = "Successfully updated site properties for $($SiteUrl): $($AppliedChanges -join ', ')"
        if ($Skipped.Count -gt 0) {
            $Results += " Skipped (not supported on group-connected sites): $($Skipped -join ', ')."
        }
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to update site properties for $($SiteUrl): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Results }
        })
}
