function Invoke-ExecSetSiteProperty {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $SiteId = $Request.Body.SiteId
    $DisplayName = $Request.Body.DisplayName

    try {
        if (-not $SiteId) {
            throw 'SiteId is required'
        }
        if (-not $TenantFilter) {
            throw 'TenantFilter is required'
        }

        $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
        $ExtraHeaders = @{
            'accept'        = 'application/json'
            'content-type'  = 'application/json'
            'odata-version' = '4.0'
        }

        $SiteLabel = if ($DisplayName) { $DisplayName } else { $SiteId }
        $PatchUri = "$($SharePointInfo.AdminUrl)/_api/SPO.Tenant/sites('$SiteId')"
        $PropertiesToSet = @{}
        $ActionDescription = ''

        # Helper: autoComplete fields may arrive as { label, value } objects — extract the value
        function Get-FieldValue($Field) {
            if ($Field -is [PSCustomObject] -and $null -ne $Field.value) {
                return $Field.value
            }
            return $Field
        }

        # Helper: strict integer parse — rejects non-integral values instead of rounding
        function Get-IntValue($Raw, [string]$Name) {
            $Parsed = 0
            if (-not [int]::TryParse([string]$Raw, [ref]$Parsed)) {
                throw "$Name must be a whole number (received '$Raw')"
            }
            return $Parsed
        }

        # Helper: strict boolean parse — accepts native booleans and 'true'/'false' strings only
        function Get-BoolValue($Raw, [string]$Name) {
            if ($Raw -is [bool]) { return $Raw }
            $Parsed = $false
            if (-not [bool]::TryParse([string]$Raw, [ref]$Parsed)) {
                throw "$Name must be true or false (received '$Raw')"
            }
            return $Parsed
        }

        # Lock State
        $RawLockState = Get-FieldValue $Request.Body.LockState
        if ($RawLockState) {
            $LockStateMap = @{
                'Unlock'    = 0
                'NoAccess'  = 1
                'ReadOnly'  = 2
            }
            $LockValue = $LockStateMap[$RawLockState]
            if ($null -eq $LockValue) {
                throw "Invalid LockState '$RawLockState'. Valid values: Unlock, NoAccess, ReadOnly"
            }
            $PropertiesToSet['LockState'] = $LockValue
            $ActionDescription = "Set lock state to '$RawLockState'"
        }

        # Sharing Capability
        $RawSharing = Get-FieldValue $Request.Body.SharingCapability
        if ($null -ne $RawSharing -and '' -ne $RawSharing) {
            $SharingLabels = @{
                0 = 'Disabled'
                1 = 'ExternalUserSharingOnly'
                2 = 'ExternalUserAndGuestSharing'
                3 = 'ExistingExternalUserSharingOnly'
            }
            $SharingValue = [int]$RawSharing
            if ($SharingValue -notin 0, 1, 2, 3) {
                throw "Invalid SharingCapability '$SharingValue'. Valid values: 0 (Disabled), 1 (ExternalUserSharingOnly), 2 (ExternalUserAndGuestSharing), 3 (ExistingExternalUserSharingOnly)"
            }
            $PropertiesToSet['SharingCapability'] = $SharingValue
            $ActionDescription = "Set sharing capability to '$($SharingLabels[$SharingValue])'"
        }

        # Storage Quota (accepts GB, converts to MB for the API)
        if ($null -ne $Request.Body.StorageMaximumLevelGB -and '' -ne $Request.Body.StorageMaximumLevelGB) {
            $MaxGB = [double]$Request.Body.StorageMaximumLevelGB
            if ($MaxGB -le 0) {
                throw 'StorageMaximumLevelGB must be a positive number'
            }
            $MaxLevel = [long]($MaxGB * 1024)
            $PropertiesToSet['StorageMaximumLevel'] = $MaxLevel

            if ($null -ne $Request.Body.StorageWarningLevelGB -and '' -ne $Request.Body.StorageWarningLevelGB) {
                $WarnGB = [double]$Request.Body.StorageWarningLevelGB
                $WarnLevel = [long]($WarnGB * 1024)
                if ($WarnLevel -lt 0 -or $WarnLevel -ge $MaxLevel) {
                    throw 'StorageWarningLevelGB must be between 0 and StorageMaximumLevelGB'
                }
                $PropertiesToSet['StorageWarningLevel'] = $WarnLevel
            } else {
                # Default warning at 90% of max
                $PropertiesToSet['StorageWarningLevel'] = [long]($MaxLevel * 0.9)
            }
            $ActionDescription = "Set storage quota to $($MaxGB) GB (warning at $([math]::Round($PropertiesToSet['StorageWarningLevel'] / 1024, 2)) GB)"
        }

        # Default Sharing Link Type (0=None/tenant default, 1=Direct, 2=Internal, 3=AnonymousAccess)
        $RawLinkType = Get-FieldValue $Request.Body.DefaultSharingLinkType
        if ($null -ne $RawLinkType -and '' -ne $RawLinkType) {
            $LinkTypeLabels = @{ 0 = 'Tenant default'; 1 = 'Direct (specific people)'; 2 = 'Internal (organization)'; 3 = 'Anyone (anonymous)' }
            $LinkTypeValue = Get-IntValue $RawLinkType 'DefaultSharingLinkType'
            if ($LinkTypeValue -notin 0, 1, 2, 3) {
                throw "Invalid DefaultSharingLinkType '$LinkTypeValue'. Valid values: 0 (tenant default), 1 (Direct), 2 (Internal), 3 (AnonymousAccess)"
            }
            $PropertiesToSet['DefaultSharingLinkType'] = $LinkTypeValue
            if ($ActionDescription) { $ActionDescription += "; default sharing link type '$($LinkTypeLabels[$LinkTypeValue])'" }
            else { $ActionDescription = "Set default sharing link type to '$($LinkTypeLabels[$LinkTypeValue])'" }
        }

        # Default Link Permission (0=None/tenant default, 1=View, 2=Edit)
        $RawLinkPerm = Get-FieldValue $Request.Body.DefaultLinkPermission
        if ($null -ne $RawLinkPerm -and '' -ne $RawLinkPerm) {
            $LinkPermLabels = @{ 0 = 'Tenant default'; 1 = 'View'; 2 = 'Edit' }
            $LinkPermValue = Get-IntValue $RawLinkPerm 'DefaultLinkPermission'
            if ($LinkPermValue -notin 0, 1, 2) {
                throw "Invalid DefaultLinkPermission '$LinkPermValue'. Valid values: 0 (tenant default), 1 (View), 2 (Edit)"
            }
            $PropertiesToSet['DefaultLinkPermission'] = $LinkPermValue
            if ($ActionDescription) { $ActionDescription += "; default link permission '$($LinkPermLabels[$LinkPermValue])'" }
            else { $ActionDescription = "Set default link permission to '$($LinkPermLabels[$LinkPermValue])'" }
        }

        # Anonymous link expiration (requires override flag)
        if ($null -ne $Request.Body.AnonymousLinkExpirationInDays -and '' -ne $Request.Body.AnonymousLinkExpirationInDays) {
            $ExpDays = Get-IntValue $Request.Body.AnonymousLinkExpirationInDays 'AnonymousLinkExpirationInDays'
            if ($ExpDays -lt 1) { throw 'AnonymousLinkExpirationInDays must be at least 1' }
            $PropertiesToSet['OverrideTenantAnonymousLinkExpirationPolicy'] = $true
            $PropertiesToSet['AnonymousLinkExpirationInDays'] = $ExpDays
            if ($ActionDescription) { $ActionDescription += "; anonymous links expire after $ExpDays days" }
            else { $ActionDescription = "Set anonymous link expiration to $ExpDays days" }
        }

        # Restricted Access Control (requires SharePoint Advanced Management licensing)
        $RawRAC = Get-FieldValue $Request.Body.RestrictedAccessControl
        if ($null -ne $RawRAC -and '' -ne $RawRAC) {
            $RACValue = Get-BoolValue $RawRAC 'RestrictedAccessControl'
            $PropertiesToSet['RestrictedAccessControl'] = $RACValue
            $RACDescription = if ($RACValue) { 'Enabled restricted access control (members only)' } else { 'Disabled restricted access control' }
            if ($ActionDescription) { $ActionDescription += "; $($RACDescription.ToLower())" }
            else { $ActionDescription = $RACDescription }
        }

        if ($PropertiesToSet.Count -eq 0) {
            throw 'No valid properties specified. Provide one of: LockState, SharingCapability, StorageMaximumLevelGB, DefaultSharingLinkType, DefaultLinkPermission, AnonymousLinkExpirationInDays, RestrictedAccessControl'
        }

        $PatchBody = $PropertiesToSet | ConvertTo-Json -Depth 5
        $null = New-GraphPOSTRequest `
            -scope "$($SharePointInfo.AdminUrl)/.default" `
            -uri $PatchUri `
            -body $PatchBody `
            -tenantid $TenantFilter `
            -type PATCH `
            -AddedHeaders $ExtraHeaders

        $Results = "Successfully updated site '$SiteLabel': $ActionDescription"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Info

        return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ Results = $Results }
        })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $ErrorText = $ErrorMessage.NormalizedError
        if ($ErrorText -match 'license|Advanced Management|not enabled for this tenant') {
            $ErrorText = "This setting requires SharePoint Advanced Management licensing, which this tenant does not appear to have. Original error: $ErrorText"
        }
        if ($PropertiesToSet -and $PropertiesToSet.ContainsKey('StorageMaximumLevel')) {
            $ErrorText = "$ErrorText If this tenant uses automatic site storage management, per-site quotas do not apply until the tenant is switched to manual site storage limits in the SharePoint admin center."
        }
        $Results = "Failed to update site property for '$SiteLabel'. Error: $ErrorText"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Error -LogData $ErrorMessage

        return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = @{ Results = $Results }
        })
    }
}
