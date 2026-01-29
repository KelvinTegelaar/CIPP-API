function Search-CIPPDbData {
    <#
    .SYNOPSIS
        Universal search function for CIPP Reporting DB data

    .DESCRIPTION
        Searches JSON objects in the CIPP Reporting DB for matching search terms.
        Supports wildcard and regular expression searches across multiple data types.
        Returns results as a flat list with Type property included.

    .PARAMETER TenantFilter
        Optional tenant domain or GUID to filter search. If not specified, searches all tenants.

    .PARAMETER SearchTerms
        Search terms to look for. Uses regex matching by default (special characters are escaped).
        Can be a single string or array of strings.

    .PARAMETER Types
        Array of data types to search. If not specified, searches all available types.
        Valid types: Users, Domains, ConditionalAccessPolicies, ManagedDevices, Organization,
        Groups, Roles, LicenseOverview, IntuneDeviceCompliancePolicies, SecureScore,
        SecureScoreControlProfiles, Mailboxes, CASMailbox, MailboxPermissions, OneDriveUsage, MailboxUsage

    .PARAMETER MatchAll
        If specified, all search terms must be found. Default is false (any term matches).

    .PARAMETER MaxResultsPerType
        Maximum number of results to return per type. Default is unlimited (0)

    .PARAMETER Limit
        Maximum total number of results to return across all types. Default is unlimited (0)

    .EXAMPLE
        Search-CIPPDbData -TenantFilter 'contoso.onmicrosoft.com' -SearchTerms 'john.doe' -Types 'Users', 'Groups'

    .EXAMPLE
        Search-CIPPDbData -SearchTerms 'admin' -Types 'Users'

    .EXAMPLE
        Search-CIPPDbData -SearchTerms 'SecurityDefaults', 'ConditionalAccess' -Types 'ConditionalAccessPolicies', 'Organization'

    .EXAMPLE
        Search-CIPPDbData -SearchTerms 'SecurityDefaults', 'ConditionalAccess' -Types 'ConditionalAccessPolicies', 'Organization'

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string[]]$SearchTerms,

        [Parameter(Mandatory = $false)]
        [ValidateSet(
            'Users', 'Domains', 'ConditionalAccessPolicies', 'ManagedDevices', 'Organization',
            'Groups', 'Roles', 'LicenseOverview', 'IntuneDeviceCompliancePolicies', 'SecureScore',
            'SecureScoreControlProfiles', 'Mailboxes', 'CASMailbox', 'MailboxPermissions',
            'OneDriveUsage', 'MailboxUsage', 'Devices', 'AllRoles', 'Licenses', 'DeviceCompliancePolicies'
        )]
        [string[]]$Types,

        [Parameter(Mandatory = $false)]
        [switch]$MatchAll,

        [Parameter(Mandatory = $false)]
        [int]$MaxResultsPerType = 0,

        [Parameter(Mandatory = $false)]
        [int]$Limit = 0
    )

    try {
        # Initialize results list
        $Results = [System.Collections.Generic.List[object]]::new()

        # Define all available types if not specified
        if (-not $Types) {
            $Types = @(
                'Users', 'Domains', 'ConditionalAccessPolicies', 'ManagedDevices', 'Organization',
                'Groups', 'Roles', 'LicenseOverview', 'IntuneDeviceCompliancePolicies', 'SecureScore',
                'SecureScoreControlProfiles', 'Mailboxes', 'CASMailbox', 'MailboxPermissions',
                'OneDriveUsage', 'MailboxUsage'
            )
        }

        # Get tenants to search - use 'allTenants' if no filter specified
        $TenantsToSearch = @()
        if ($TenantFilter) {
            $TenantsToSearch = @($TenantFilter)
        } else {
            # Use 'allTenants' to search across all tenants
            $TenantsToSearch = @('allTenants')
            Write-Verbose 'Searching all tenants'
        }

        # Process each data type
        :typeLoop foreach ($Type in $Types) {
            Write-Verbose "Searching type: $Type"
            $TypeResultCount = 0

            # Search across all tenants
            foreach ($Tenant in $TenantsToSearch) {
                if (-not $Tenant) { continue }

                try {
                    # Get items for this type and tenant
                    $Items = Get-CIPPDbItem -TenantFilter $Tenant -Type $Type | Where-Object { $_.RowKey -notlike '*-Count' }
                    Write-Verbose "Found $(@($Items).Count) items for type '$Type' in tenant '$Tenant'"

                    if ($Items) {
                        foreach ($Item in $Items) {
                            # Data is already in JSON format, do a quick text search first
                            if (-not $Item.Data) { continue }

                            # Check if any search term matches in the JSON string
                            $IsMatch = $false

                            if ($MatchAll) {
                                # All terms must match
                                $IsMatch = $true
                                foreach ($SearchTerm in $SearchTerms) {
                                    $SearchPattern = [regex]::Escape($SearchTerm)
                                    if ($Item.Data -notmatch $SearchPattern) {
                                        $IsMatch = $false
                                        break
                                    }
                                }
                            } else {
                                # Any term can match (default)
                                foreach ($SearchTerm in $SearchTerms) {
                                    $SearchPattern = [regex]::Escape($SearchTerm)
                                    if ($Item.Data -match $SearchPattern) {
                                        $IsMatch = $true
                                        break
                                    }
                                }
                            }

                            # Only parse JSON if we have a match
                            if ($IsMatch) {
                                try {
                                    $Data = $Item.Data | ConvertFrom-Json
                                    $ResultItem = [PSCustomObject]@{
                                        Tenant    = $Item.PartitionKey
                                        Type      = $Type
                                        RowKey    = $Item.RowKey
                                        Data      = $Data
                                        Timestamp = $Item.Timestamp
                                    }
                                    $Results.Add($ResultItem)
                                    $TypeResultCount++

                                    # Check total limit first
                                    if ($Limit -gt 0 -and $Results.Count -ge $Limit) {
                                        Write-Verbose "Reached total limit of $Limit results"
                                        break typeLoop
                                    }

                                    # Check max results per type
                                    if ($MaxResultsPerType -gt 0 -and $TypeResultCount -ge $MaxResultsPerType) {
                                        Write-Verbose "Reached max results per type ($MaxResultsPerType) for type '$Type'"
                                        continue typeLoop
                                    }
                                } catch {
                                    Write-Verbose "Failed to parse JSON for $($Item.RowKey): $($_.Exception.Message)"
                                }
                            }
                        }
                    }

                } catch {
                    Write-Verbose "Error searching type '$Type' for tenant '$Tenant': $($_.Exception.Message)"
                }
            }
        }

        Write-Verbose "Found $($Results.Count) total results"
        # Return results as flat list
        return $Results.ToArray()

    } catch {
        Write-LogMessage -API 'UniversalSearch' -tenant $TenantFilter -message "Failed to perform universal search: $($_.Exception.Message)" -sev Error
        throw
    }
}
