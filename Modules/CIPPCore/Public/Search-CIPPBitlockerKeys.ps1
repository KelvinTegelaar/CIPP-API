function Search-CIPPBitlockerKeys {
    <#
    .SYNOPSIS
        Search for BitLocker recovery keys and merge with device information

    .DESCRIPTION
        Searches cached BitLocker recovery keys and automatically enriches results with device information
        by cross-referencing the deviceId with Devices or ManagedDevices data.

    .PARAMETER TenantFilter
        Tenant domain or GUID to search. If not specified, searches all tenants.

    .PARAMETER KeyId
        Optional BitLocker recovery key ID to search for. If not specified, returns all keys.

    .PARAMETER DeviceId
        Optional device ID to filter BitLocker keys by device.

    .PARAMETER SearchTerms
        Optional search terms to filter results (searches across all BitLocker key fields).

    .PARAMETER Limit
        Maximum number of results to return. Default is unlimited (0).

    .EXAMPLE
        Search-CIPPBitlockerKeys -TenantFilter 'contoso.onmicrosoft.com' -KeyId '8911a878-b631-47e8-b5e8-bcb00e586c74'

    .EXAMPLE
        Search-CIPPBitlockerKeys -DeviceId '1b418b08-a0c6-4db1-95cd-08a9b943b70e'

    .EXAMPLE
        Search-CIPPBitlockerKeys -SearchTerms 'device-name'

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $false)]
        [string]$KeyId,

        [Parameter(Mandatory = $false)]
        [string]$DeviceId,

        [Parameter(Mandatory = $false)]
        [string[]]$SearchTerms,

        [Parameter(Mandatory = $false)]
        [int]$Limit = 0
    )

    try {
        # Build search parameters
        $SearchParams = @{
            Types = @('BitlockerKeys')
        }

        if ($TenantFilter) {
            $SearchParams.TenantFilter = @($TenantFilter)
        }

        # Determine what to search for
        if ($KeyId) {
            $SearchParams.SearchTerms = @($KeyId)
        } elseif ($DeviceId) {
            $SearchParams.SearchTerms = @($DeviceId)
        } elseif ($SearchTerms) {
            $SearchParams.SearchTerms = $SearchTerms
        } else {
            # If no search criteria, search for a pattern that matches any GUID or just get all
            $SearchParams.SearchTerms = @('[a-f0-9]{8}-')
        }

        if ($Limit -gt 0) {
            $SearchParams.Limit = $Limit
        }

        Write-Verbose "Searching for BitLocker keys with params: $($SearchParams | ConvertTo-Json -Compress)"

        # Search for BitLocker keys
        $BitlockerResults = Search-CIPPDbData @SearchParams

        if (-not $BitlockerResults -or $BitlockerResults.Count -eq 0) {
            Write-Verbose 'No BitLocker keys found'
            return @()
        }

        Write-Verbose "Found $($BitlockerResults.Count) BitLocker key(s)"

        # Enrich each result with device information
        $EnrichedResults = foreach ($Result in $BitlockerResults) {
            $BitlockerData = $Result.Data
            $DeviceInfo = $null

            if ($BitlockerData.deviceId) {
                Write-Verbose "Looking up device info for deviceId: $($BitlockerData.deviceId)"

                # Try to find device in Devices collection first
                try {
                    $DeviceSearch = Search-CIPPDbData -TenantFilter $Result.Tenant -Types 'Devices' -SearchTerms $BitlockerData.deviceId -Limit 1
                    if ($DeviceSearch -and $DeviceSearch.Count -gt 0) {
                        $DeviceInfo = $DeviceSearch[0].Data
                        Write-Verbose "Found device in Devices collection: $($DeviceInfo.displayName)"
                    }
                } catch {
                    Write-Verbose "Error searching Devices: $($_.Exception.Message)"
                }

                # If not found in Devices, try ManagedDevices
                if (-not $DeviceInfo) {
                    try {
                        $DeviceSearch = Search-CIPPDbData -TenantFilter $Result.Tenant -Types 'ManagedDevices' -SearchTerms $BitlockerData.deviceId -Limit 1
                        if ($DeviceSearch -and $DeviceSearch.Count -gt 0) {
                            $DeviceInfo = $DeviceSearch[0].Data
                            Write-Verbose "Found device in ManagedDevices collection: $($DeviceInfo.deviceName)"
                        }
                    } catch {
                        Write-Verbose "Error searching ManagedDevices: $($_.Exception.Message)"
                    }
                }
            }

            # Create enriched result
            $EnrichedData = [PSCustomObject]@{
                # BitLocker key information
                id              = $BitlockerData.id
                createdDateTime = $BitlockerData.createdDateTime
                volumeType      = $BitlockerData.volumeType
                deviceId        = $BitlockerData.deviceId

                # Device information (if found)
                deviceName      = if ($DeviceInfo) { $DeviceInfo.displayName ?? $DeviceInfo.deviceName } else { $null }
                operatingSystem = if ($DeviceInfo) { $DeviceInfo.operatingSystem } else { $null }
                osVersion       = if ($DeviceInfo) { $DeviceInfo.operatingSystemVersion ?? $DeviceInfo.osVersion } else { $null }
                lastSignIn      = if ($DeviceInfo) { $DeviceInfo.approximateLastSignInDateTime ?? $DeviceInfo.lastSyncDateTime } else { $null }
                accountEnabled  = if ($DeviceInfo) { $DeviceInfo.accountEnabled ?? $DeviceInfo.isCompliant } else { $null }
                trustType       = if ($DeviceInfo) { $DeviceInfo.trustType ?? $DeviceInfo.joinType } else { $null }

                # Metadata
                deviceFound     = $null -ne $DeviceInfo
            }

            [PSCustomObject]@{
                Tenant    = $Result.Tenant
                Type      = $Result.Type
                RowKey    = $Result.RowKey
                Data      = $EnrichedData
                Timestamp = $Result.Timestamp
            }
        }

        Write-Verbose "Returning $($EnrichedResults.Count) enriched result(s)"
        return $EnrichedResults

    } catch {
        Write-LogMessage -API 'SearchBitlockerKeys' -tenant $TenantFilter -message "Failed to search BitLocker keys: $($_.Exception.Message)" -sev Error
        throw
    }
}
