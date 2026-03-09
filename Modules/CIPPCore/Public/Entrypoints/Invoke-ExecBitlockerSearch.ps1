function Invoke-ExecBitlockerSearch {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.Device.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        # Get search parameters from query string or POST body
        $KeyId = $Request.Query.keyId ?? $Request.Body.keyId
        $DeviceId = $Request.Query.deviceId ?? $Request.Body.deviceId
        $Limit = $Request.Query.limit ?? $Request.Body.limit ?? 0

        # Handle tenant filtering with access control
        $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList

        $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
        if ($AllowedTenants -notcontains 'AllTenants') {
            if ($TenantFilter) {
                # Verify user has access to requested tenant
                $TenantList = Get-Tenants | Select-Object -ExpandProperty defaultDomainName
                if ($TenantList -notcontains $TenantFilter) {
                    return [HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::Forbidden
                        Body       = @{
                            error = "Access denied to tenant: $TenantFilter"
                        }
                    }
                }
            } else {
                $TenantFilter = Get-Tenants | Select-Object -ExpandProperty defaultDomainName
            }
        } elseif (-not $TenantFilter) {
            $TenantFilter = 'allTenants'
        }

        # Build parameters for Search-CIPPBitlockerKeys
        $SearchParams = @{}

        if ($TenantFilter) {
            $SearchParams.TenantFilter = $TenantFilter
            Write-Information "Filtering by tenant: $TenantFilter"
        }

        if ($KeyId) {
            $SearchParams.KeyId = $KeyId
            Write-Information "Searching for key ID: $KeyId"
        } elseif ($DeviceId) {
            $SearchParams.DeviceId = $DeviceId
            Write-Information "Searching for device ID: $DeviceId"
        } else {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{
                    error = 'No search criteria provided. Please provide keyId or deviceId.'
                }
            }
        }

        if ($Limit -gt 0) {
            $SearchParams.Limit = [int]$Limit
        }

        # Execute the search
        $Results = Search-CIPPBitlockerKeys @SearchParams

        Write-Information "Found $($Results.Count) BitLocker key record(s)"

        # Format results for output
        $OutputResults = @($Results | ForEach-Object {
                [PSCustomObject]@{
                    tenant          = $_.Tenant
                    keyId           = $_.Data.id
                    createdDateTime = $_.Data.createdDateTime
                    volumeType      = $_.Data.volumeType
                    deviceId        = $_.Data.deviceId
                    deviceName      = $_.Data.deviceName
                    operatingSystem = $_.Data.operatingSystem
                    osVersion       = $_.Data.osVersion
                    lastSignIn      = $_.Data.lastSignIn
                    accountEnabled  = $_.Data.accountEnabled
                    trustType       = $_.Data.trustType
                    deviceFound     = $_.Data.deviceFound
                    timestamp       = $_.Timestamp
                }
            })

        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{
                Results = $OutputResults
                Count   = $OutputResults.Count
            }
        }

    } catch {
        Write-Information "Error occurred during BitLocker key search: $($_.Exception.Message)"
        Write-Information $_.InvocationInfo.PositionMessage
        return [HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = @{
                error = "Failed to search for BitLocker keys: $($_.Exception.Message)"
            }
        }
    }
}
