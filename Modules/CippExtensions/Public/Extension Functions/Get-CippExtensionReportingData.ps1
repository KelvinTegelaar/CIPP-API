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
        [switch]$IncludeMailboxes
    )

    try {
        $Return = @{}

        # Direct mappings - loop through items and parse each .Data property (filter out count entries)
        $UsersItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'Users' | Where-Object { $_.RowKey -notlike '*-Count' }
        $Return.Users = if ($UsersItems) { $UsersItems | ForEach-Object { $_.Data | ConvertFrom-Json } } else { @() }

        $DomainsItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'Domains' | Where-Object { $_.RowKey -notlike '*-Count' }
        $Return.Domains = if ($DomainsItems) { $DomainsItems | ForEach-Object { $_.Data | ConvertFrom-Json } } else { @() }

        $ConditionalAccessItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'ConditionalAccessPolicies' | Where-Object { $_.RowKey -notlike '*-Count' }
        $Return.ConditionalAccess = if ($ConditionalAccessItems) { $ConditionalAccessItems | ForEach-Object { $_.Data | ConvertFrom-Json } } else { @() }

        $ManagedDevicesItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'ManagedDevices' | Where-Object { $_.RowKey -notlike '*-Count' }
        $Return.Devices = if ($ManagedDevicesItems) { $ManagedDevicesItems | ForEach-Object { $_.Data | ConvertFrom-Json } } else { @() }

        $OrganizationItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'Organization' | Where-Object { $_.RowKey -notlike '*-Count' }
        $Return.Organization = if ($OrganizationItems) { ($OrganizationItems | ForEach-Object { $_.Data | ConvertFrom-Json } | Select-Object -First 1) } else { $null }

        # Groups with inline members (members are now in each group object)
        $GroupsItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'Groups' | Where-Object { $_.RowKey -notlike '*-Count' }
        $Return.Groups = if ($GroupsItems) { $GroupsItems | ForEach-Object { $_.Data | ConvertFrom-Json } } else { @() }

        # Roles with inline members (members are now in each role object)
        $RolesItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'Roles' | Where-Object { $_.RowKey -notlike '*-Count' }
        $Return.AllRoles = if ($RolesItems) { $RolesItems | ForEach-Object { $_.Data | ConvertFrom-Json } } else { @() }

        # License mapping with property translation to maintain compatibility
        $LicenseItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'LicenseOverview' | Where-Object { $_.RowKey -notlike '*-Count' }
        if ($LicenseItems) {
            $ParsedLicenseData = $LicenseItems | ForEach-Object { $_.Data | ConvertFrom-Json }
            $Return.Licenses = $ParsedLicenseData | Select-Object @{N = 'skuId'; E = { $_.skuId } },
            @{N = 'skuPartNumber'; E = { $_.skuPartNumber } },
            @{N = 'consumedUnits'; E = { $_.CountUsed } },
            @{N = 'prepaidUnits'; E = { @{enabled = $_.TotalLicenses } } }
        } else {
            $Return.Licenses = @()
        }

        # Intune policies (renamed from DeviceCompliancePolicies to IntuneDeviceCompliancePolicies)
        $IntunePoliciesItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'IntuneDeviceCompliancePolicies' | Where-Object { $_.RowKey -notlike '*-Count' }
        $Return.DeviceCompliancePolicies = if ($IntunePoliciesItems) { $IntunePoliciesItems | ForEach-Object { $_.Data | ConvertFrom-Json } } else { @() }

        # Secure Score
        $SecureScoreItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'SecureScore' | Where-Object { $_.RowKey -notlike '*-Count' }
        $Return.SecureScore = if ($SecureScoreItems) { $SecureScoreItems | ForEach-Object { $_.Data | ConvertFrom-Json } } else { @() }

        # Secure Score Control Profiles
        $SecureScoreControlProfilesItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'SecureScoreControlProfiles' | Where-Object { $_.RowKey -notlike '*-Count' }
        $Return.SecureScoreControlProfiles = if ($SecureScoreControlProfilesItems) { $SecureScoreControlProfilesItems | ForEach-Object { $_.Data | ConvertFrom-Json } } else { @() }

        # Mailboxes (optional - requires separate cache run)
        if ($IncludeMailboxes) {
            $MailboxesItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'Mailboxes' | Where-Object { $_.RowKey -notlike '*-Count' }
            $Return.Mailboxes = if ($MailboxesItems) { $MailboxesItems | ForEach-Object { $_.Data | ConvertFrom-Json } } else { @() }

            $CASMailboxItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'CASMailbox' | Where-Object { $_.RowKey -notlike '*-Count' }
            $Return.CASMailbox = if ($CASMailboxItems) { $CASMailboxItems | ForEach-Object { $_.Data | ConvertFrom-Json } } else { @() }

            $MailboxPermissionsItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'MailboxPermissions' | Where-Object { $_.RowKey -notlike '*-Count' }
            $Return.MailboxPermissions = if ($MailboxPermissionsItems) { $MailboxPermissionsItems | ForEach-Object { $_.Data | ConvertFrom-Json } } else { @() }

            $OneDriveUsageItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'OneDriveUsage' | Where-Object { $_.RowKey -notlike '*-Count' }
            $Return.OneDriveUsage = if ($OneDriveUsageItems) { $OneDriveUsageItems | ForEach-Object { $_.Data | ConvertFrom-Json } } else { @() }

            $MailboxUsageItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'MailboxUsage' | Where-Object { $_.RowKey -notlike '*-Count' }
            $Return.MailboxUsage = if ($MailboxUsageItems) { $MailboxUsageItems | ForEach-Object { $_.Data | ConvertFrom-Json } } else { @() }
        }

        return $Return

    } catch {
        Write-LogMessage -API 'ExtensionCache' -tenant $TenantFilter -message "Failed to retrieve extension reporting data: $($_.Exception.Message)" -sev Error
        throw
    }
}
