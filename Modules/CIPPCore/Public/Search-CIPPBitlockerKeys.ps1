function Search-CIPPBitlockerKeys {
    <#
    .SYNOPSIS
        Search for BitLocker recovery keys and merge with device information

    .DESCRIPTION
        Searches cached BitLocker recovery keys and automatically enriches results with device information
        by cross-referencing the deviceId with Devices or ManagedDevices data.

    .PARAMETER TenantFilter
        Tenant domains or GUIDs to search. If not specified, searches all tenants.

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
        [string[]]$TenantFilter,

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
            # Search terms are matched literally; every cached row is a JSON object, so '{' returns all keys
            $SearchParams.SearchTerms = @('{')
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

        # Each device type is read once per tenant and indexed by every GUID in its rows, which finds the same
        # first matching row as Search-CIPPDbData -SearchTerms <deviceId> -Limit 1 without a table read per key
        $DeviceIndexes = @{}
        $FindDevice = {
            param($Tenant, $Type, $Id)
            if (-not $Tenant) { return }
            if ($Id -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
                try { return (Search-CIPPDbData -TenantFilter $Tenant -Types $Type -SearchTerms $Id -Limit 1 | Select-Object -First 1).Data } catch { Write-Verbose "Error searching $($Type): $($_.Exception.Message)"; return }
            }
            if (-not $DeviceIndexes.ContainsKey($Type)) {
                $Rows = @(try { Get-CIPPDbItem -TenantFilter $Tenant -Type $Type | Where-Object { $_.RowKey -notlike '*-Count' -and $_.Data } } catch { Write-Verbose "Error searching $($Type): $($_.Exception.Message)" })
                $DeviceIndexes[$Type] = [CIPP.CippIndex]::Build($Rows, @(foreach ($Row in $Rows) { , ([regex]::Matches($Row.Data, '(?i)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}').Value ?? $null) }))
            }
            foreach ($Row in $DeviceIndexes[$Type].Find($Id)) {
                try { return ($Row.Data | ConvertFrom-Json) } catch { Write-Verbose "Failed to parse JSON for $($Row.RowKey): $($_.Exception.Message)" }
            }
        }

        # Enrich one tenant at a time so only that tenant's devices are held, keeping the input order
        $Results = @($BitlockerResults)
        $ByTenant = [ordered]@{}
        for ($i = 0; $i -lt $Results.Count; $i++) {
            $Tenant = [string]$Results[$i].Tenant
            if (-not $ByTenant.Contains($Tenant)) { $ByTenant[$Tenant] = [System.Collections.Generic.List[int]]::new() }
            $ByTenant[$Tenant].Add($i)
        }
        $EnrichedResults = [object[]]::new($Results.Count)
        foreach ($Positions in $ByTenant.Values) {
            $DeviceIndexes.Clear()
            foreach ($Position in $Positions) {
                $Result = $Results[$Position]
                $BitlockerData = $Result.Data
                $DeviceInfo = $null

                if ($BitlockerData.deviceId) {
                    Write-Verbose "Looking up device info for deviceId: $($BitlockerData.deviceId)"
                    $DeviceInfo = & $FindDevice $Result.Tenant 'Devices' $BitlockerData.deviceId
                    if (-not $DeviceInfo) { $DeviceInfo = & $FindDevice $Result.Tenant 'ManagedDevices' $BitlockerData.deviceId }
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

                $EnrichedResults[$Position] = [PSCustomObject]@{
                    Tenant    = $Result.Tenant
                    Type      = $Result.Type
                    RowKey    = $Result.RowKey
                    Data      = $EnrichedData
                    Timestamp = $Result.Timestamp
                }
            }
        }

        Write-Verbose "Returning $($EnrichedResults.Count) enriched result(s)"
        return $EnrichedResults

    } catch {
        Write-LogMessage -API 'SearchBitlockerKeys' -tenant "$TenantFilter" -message "Failed to search BitLocker keys: $($_.Exception.Message)" -sev Error
        throw
    }
}
