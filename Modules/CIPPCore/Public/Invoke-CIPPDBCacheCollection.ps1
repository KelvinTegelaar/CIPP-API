function Invoke-CIPPDBCacheCollection {
    <#
    .SYNOPSIS
        Execute a grouped collection of DB cache functions for a tenant

    .DESCRIPTION
        Runs all Set-CIPPDBCache* functions belonging to a collection type sequentially
        within a single invocation. This reduces orchestrator activity count by ~10x
        compared to individual per-type activities, eliminating replay overhead.

        Collection types map to license categories:
        - Graph:              Core tenant data (no special license needed)
        - ExchangeConfig:     Exchange Online policy/config data
        - ExchangeData:       Mailboxes, CAS mailboxes, usage reports
        - ConditionalAccess:  CA policies and registration details
        - IdentityProtection: Risky users/SPs, risk detections, PIM
        - Intune:             Managed devices, policies, app protection

    .PARAMETER CollectionType
        The group of cache functions to execute

    .PARAMETER TenantFilter
        The tenant domain to collect data for

    .PARAMETER QueueId
        Optional queue ID for progress tracking

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Graph', 'ExchangeConfig', 'ExchangeData', 'ConditionalAccess', 'IdentityProtection', 'Intune')]
        [string]$CollectionType,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [string]$QueueId
    )

    # Canonical collection definitions — single source of truth for grouping
    $Collections = @{
        Graph              = @(
            'Users'
            'Groups'
            'Guests'
            'ServicePrincipals'
            'Apps'
            'Devices'
            'Organization'
            'Roles'
            'AdminConsentRequestPolicy'
            'AuthorizationPolicy'
            'AuthenticationMethodsPolicy'
            'DeviceSettings'
            'DirectoryRecommendations'
            'CrossTenantAccessPolicy'
            'DefaultAppManagementPolicy'
            'Settings'
            'SecureScore'
            'PIMSettings'
            'Domains'
            'B2BManagementPolicy'
            'DeviceRegistrationPolicy'
            'OAuth2PermissionGrants'
            'AppRoleAssignments'
            'LicenseOverview'
            'MFAState'
            'BitlockerKeys'
        )
        ExchangeConfig     = @(
            'ExoAntiPhishPolicies'
            'ExoMalwareFilterPolicies'
            'ExoSafeLinksPolicies'
            'ExoSafeAttachmentPolicies'
            'ExoTransportRules'
            'ExoDkimSigningConfig'
            'ExoOrganizationConfig'
            'ExoAcceptedDomains'
            'ExoHostedContentFilterPolicy'
            'ExoHostedOutboundSpamFilterPolicy'
            'ExoAntiPhishPolicy'
            'ExoSafeLinksPolicy'
            'ExoSafeAttachmentPolicy'
            'ExoMalwareFilterPolicy'
            'ExoAtpPolicyForO365'
            'ExoQuarantinePolicy'
            'ExoRemoteDomain'
            'ExoSharingPolicy'
            'ExoAdminAuditLogConfig'
            'ExoPresetSecurityPolicy'
            'ExoTenantAllowBlockList'
        )
        ExchangeData       = @(
            'CASMailboxes'
            'MailboxUsage'
            'OneDriveUsage'
        )
        ConditionalAccess  = @(
            'ConditionalAccessPolicies'
            'CredentialUserRegistrationDetails'
            'UserRegistrationDetails'
        )
        IdentityProtection = @(
            'RiskyUsers'
            'RiskyServicePrincipals'
            'ServicePrincipalRiskDetections'
            'RiskDetections'
            'RoleEligibilitySchedules'
            'RoleAssignmentScheduleInstances'
            'RoleManagementPolicies'
        )
        Intune             = @(
            'ManagedDevices'
            'IntunePolicies'
            'ManagedDeviceEncryptionStates'
            'IntuneAppProtectionPolicies'
            'DetectedApps'
        )
    }

    $CacheTypes = $Collections[$CollectionType]
    if (-not $CacheTypes -or $CacheTypes.Count -eq 0) {
        throw "Unknown or empty collection type: $CollectionType"
    }

    Write-Information "Starting $CollectionType collection for $TenantFilter ($($CacheTypes.Count) cache types)"

    $SuccessCount = 0
    $FailedCount = 0
    $Errors = [System.Collections.Generic.List[string]]::new()

    foreach ($CacheType in $CacheTypes) {
        $FullFunctionName = "Set-CIPPDBCache$CacheType"
        try {
            $Function = Get-Command -Name $FullFunctionName -ErrorAction SilentlyContinue
            if (-not $Function) {
                throw "Function $FullFunctionName not found"
            }

            $Params = @{ TenantFilter = $TenantFilter }
            if ($QueueId) { $Params.QueueId = $QueueId }

            Write-Information "  [$CollectionType] Collecting $CacheType for $TenantFilter"
            & $FullFunctionName @Params
            $SuccessCount++
        } catch {
            $FailedCount++
            $Errors.Add("$CacheType : $($_.Exception.Message)")
            Write-Warning "  [$CollectionType] Failed $CacheType for $TenantFilter : $($_.Exception.Message)"
        }
    }

    $Summary = "$CollectionType collection for $TenantFilter completed - $SuccessCount succeeded, $FailedCount failed out of $($CacheTypes.Count)"
    Write-Information $Summary

    if ($FailedCount -gt 0) {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "$Summary. Errors: $($Errors -join '; ')" -sev Warning
    }

    return @{
        CollectionType = $CollectionType
        TenantFilter   = $TenantFilter
        Success        = $SuccessCount
        Failed         = $FailedCount
        Total          = $CacheTypes.Count
        Errors         = @($Errors)
    }
}
