function Get-CippExtensionReportingData {
    <#
    .SYNOPSIS
        Retrieves cached data from CIPP Reporting DB for extension sync

    .DESCRIPTION
        This function replaces Get-ExtensionCacheData by retrieving data from the new CIPP Reporting DB
        instead of the legacy CacheExtensionSync table. It handles property mappings and data transformations
        to maintain compatibility with existing extension sync code.

    .PARAMETER TenantFilter
        The tenant to retrieve data for

    .PARAMETER IncludeMailboxes
        Include mailbox data (requires separate cache run with Type 'Mailboxes')

    .PARAMETER SkipMailboxPermissions
        With -IncludeMailboxes, leave out MailboxPermissions (the whole tenant's permission set) for callers that
        do not read it.

    .EXAMPLE
        $ExtensionCache = Get-CippExtensionReportingData -TenantFilter 'contoso.onmicrosoft.com'

    .EXAMPLE
        $ExtensionCache = Get-CippExtensionReportingData -TenantFilter 'contoso.onmicrosoft.com' -IncludeMailboxes

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeMailboxes,

        [Parameter(Mandatory = $false)]
        [switch]$SkipMailboxPermissions
    )

    try {
        $Return = @{}

        # Parse each type straight off the row stream, so a type's raw rows are released before the next type
        # is read instead of every type's raw rows staying pinned beside the parsed objects until return.
        # Same shapes as before: no rows -> $null, one row -> the object, several -> an array.
        $Read = {
            param($Type)
            Get-CIPPDbItem -TenantFilter $TenantFilter -Type $Type | Where-Object { $_.RowKey -notlike '*-Count' } | ForEach-Object { $_.Data | ConvertFrom-Json }
        }

        $Return.Users = & $Read 'Users'
        $Return.Domains = & $Read 'Domains'
        $Return.ConditionalAccess = & $Read 'ConditionalAccessPolicies'
        $Return.Devices = & $Read 'ManagedDevices'

        $Return.Organization = & $Read 'Organization' | Select-Object -First 1

        # Groups and Roles carry their members inline
        $Return.Groups = & $Read 'Groups'
        $Return.AllRoles = & $Read 'Roles'

        # License mapping with property translation to maintain compatibility
        $ParsedLicenseData = & $Read 'LicenseOverview'
        if ($null -ne $ParsedLicenseData) {
            $Return.Licenses = $ParsedLicenseData | Select-Object @{N = 'skuId'; E = { $_.skuId } },
            @{N = 'skuPartNumber'; E = { $_.skuPartNumber } },
            @{N = 'consumedUnits'; E = { $_.CountUsed } },
            @{N = 'prepaidUnits'; E = { @{enabled = $_.TotalLicenses } } },
            @{N = 'TermInfo'; E = { @($_.TermInfo) } },
            @{N = 'servicePlans'; E = { $_.ServicePlans } }
        } else {
            $Return.Licenses = @()
        }

        # Intune policies (renamed from DeviceCompliancePolicies to IntuneDeviceCompliancePolicies)
        $Return.DeviceCompliancePolicies = & $Read 'IntuneDeviceCompliancePolicies'
        $Return.SecureScore = & $Read 'SecureScore'
        $Return.SecureScoreControlProfiles = & $Read 'SecureScoreControlProfiles'

        # Mailboxes (optional - requires separate cache run)
        if ($IncludeMailboxes) {
            $Return.Mailboxes = & $Read 'Mailboxes'
            $Return.CASMailbox = & $Read 'CASMailbox'
            if (-not $SkipMailboxPermissions) {
                $Return.MailboxPermissions = & $Read 'MailboxPermissions'
            }
            $Return.OneDriveUsage = & $Read 'OneDriveUsage'
            $Return.MailboxUsage = & $Read 'MailboxUsage'
        }

        return $Return

    } catch {
        Write-LogMessage -API 'ExtensionCache' -tenant $TenantFilter -message "Failed to retrieve extension reporting data: $($_.Exception.Message)" -sev Error
        throw
    }
}
