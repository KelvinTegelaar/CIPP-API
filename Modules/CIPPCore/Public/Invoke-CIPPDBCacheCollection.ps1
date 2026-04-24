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
        [ValidateSet('Graph', 'ExchangeConfig', 'ExchangeData', 'ConditionalAccess', 'IdentityProtection', 'Intune', 'Compliance', 'CopilotUsage')]
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
            'OfficeActivations'
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
            'MDEOnboarding'
        )
        Compliance         = @(
            'SensitivityLabels'
            'DlpCompliancePolicies'
        )
        CopilotUsage       = @(
            'CopilotUsageUserDetail'
            'CopilotUserCountSummary'
            'CopilotUserCountTrend'
            'CopilotReadinessActivity'
        )
    }

    $CacheTypes = $Collections[$CollectionType]
    if (-not $CacheTypes -or $CacheTypes.Count -eq 0) {
        throw "Unknown or empty collection type: $CollectionType"
    }

    Write-Information "Starting $CollectionType collection for $TenantFilter ($($CacheTypes.Count) cache types)"

    $CollectionStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $SuccessCount = 0
    $FailedCount = 0
    $Errors = [System.Collections.Generic.List[string]]::new()
    $Timings = [System.Collections.Generic.List[string]]::new()

    foreach ($CacheType in $CacheTypes) {
        $FullFunctionName = "Set-CIPPDBCache$CacheType"
        $ItemStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $Function = Get-Command -Name $FullFunctionName -ErrorAction SilentlyContinue
            if (-not $Function) {
                throw "Function $FullFunctionName not found"
            }

            $Params = @{ TenantFilter = $TenantFilter }
            if ($QueueId) { $Params.QueueId = $QueueId }

            Write-Information "  [$CollectionType] Collecting $CacheType for $TenantFilter"
            & $FullFunctionName @Params
            $ItemStopwatch.Stop()
            $ElapsedSeconds = [math]::Round($ItemStopwatch.Elapsed.TotalSeconds, 3)
            $Timings.Add("$CacheType : ${ElapsedSeconds}s")
            Write-Information "  [$CollectionType] Completed $CacheType for $TenantFilter - Took ${ElapsedSeconds} seconds"
            $SuccessCount++
        } catch {
            $ItemStopwatch.Stop()
            $ElapsedSeconds = [math]::Round($ItemStopwatch.Elapsed.TotalSeconds, 3)
            $FailedCount++
            $Errors.Add("$CacheType : $($_.Exception.Message)")
            $Timings.Add("$CacheType : ${ElapsedSeconds}s (FAILED)")
            Write-Warning "  [$CollectionType] Failed $CacheType for $TenantFilter after ${ElapsedSeconds} seconds: $($_.Exception.Message)"
        }
    }

    $CollectionStopwatch.Stop()
    $TotalElapsed = [math]::Round($CollectionStopwatch.Elapsed.TotalSeconds, 3)
    $Summary = "$CollectionType collection for $TenantFilter completed in ${TotalElapsed} seconds - $SuccessCount succeeded, $FailedCount failed out of $($CacheTypes.Count)"
    Write-Information $Summary
    Write-Information "  Timings: $($Timings -join ' | ')"

    if ($FailedCount -gt 0) {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "$Summary. Errors: $($Errors -join '; ')" -sev Warning
    }

    return @{
        CollectionType = $CollectionType
        TenantFilter   = $TenantFilter
        Success        = $SuccessCount
        Failed         = $FailedCount
        Total          = $CacheTypes.Count
        TotalSeconds   = $TotalElapsed
        Timings        = @($Timings)
        Errors         = @($Errors)
    }
}
