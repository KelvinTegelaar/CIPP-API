function Invoke-ListDefenderIndicators {
    <#
    .FUNCTIONALITY
        Entrypoint,TenantGroup
    .ROLE
        Security.Defender.Read
    .DESCRIPTION
        Lists the Microsoft Defender for Endpoint custom indicators (file hashes, certificates, IP addresses, URLs and domains) of a tenant with their action: Allowed, Audit, Warn, Block or BlockAndRemediate. A single tenant is read live from Defender unless UseReportDB is set. AllTenants and tenant groups read the reporting database cache for the caller's permitted tenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    # Serve a single tenant from the reporting database cache instead of live Defender.
    $UseReportDB = $Request.Query.UseReportDB -eq $true

    if (-not $TenantFilter) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'tenantFilter is required' }
            })
    }

    if (-not $UseReportDB -and $TenantFilter -ne 'AllTenants') {
        try {
            $Body = @(foreach ($Indicator in (Get-CIPPDefenderIndicator -TenantFilter $TenantFilter)) {
                    $Indicator.Tenant = $TenantFilter
                    $Indicator
                })
            $StatusCode = [HttpStatusCode]::OK
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Message = "Failed to read the Defender indicators: $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Request.Headers -API 'ListDefenderIndicators' -tenant $TenantFilter -message $Message -sev Error -LogData $ErrorMessage
            $Body = @{ Results = $Message }
            $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
        }
        return ([HttpResponseContext]@{
                StatusCode = $StatusCode
                Body       = $Body
            })
    }

    $ManualPagination = $Request.Query.manualPagination -eq $true
    $StampTenant = $TenantFilter -ne 'AllTenants' -or -not $ManualPagination
    $Tally = @{ Total = 0; Failed = 0 }
    $ReadIndicators = {
        param($Tenant)
        try {
            $Rows = @(if ($TenantFilter -eq 'AllTenants') {
                    Get-CIPPDbItem -Partition $Tenant -Type 'DefenderIndicators'
                } else {
                    Get-CIPPDbItem -TenantFilter $Tenant -Type 'DefenderIndicators'
                })
            if ($Rows.Count -eq 0) {
                throw [System.Management.Automation.ItemNotFoundException]::new("No Defender indicators cached for $Tenant. Sync the report data first.")
            }
            $Count = $null
            $Indicators = @(foreach ($Row in $Rows) {
                    if ($Row.RowKey -eq 'DefenderIndicators-Count') {
                        if ($null -ne $Row.DataCount) { $Count = [int]$Row.DataCount }
                        continue
                    }
                    $Indicator = [CIPP.CippJson]::ConvertFromJson($Row.Data, $null)
                    if ($Indicator -isnot [pscustomobject] -or -not $Indicator.id) { throw "A cached Defender indicator row for $Tenant could not be read" }
                    $Indicator.PSObject.Properties.Add([psnoteproperty]::new('CacheTimestamp', $Row.Timestamp))
                    if ($StampTenant) { $Indicator.PSObject.Properties.Add([psnoteproperty]::new('Tenant', $Tenant)) }
                    $Indicator
                })
            if ($null -eq $Count -or $Count -ne $Indicators.Count) { throw "The Defender indicator cache for $Tenant is incomplete. Sync the report data again." }
            $Tally.Total++
            $Indicators
        } catch [System.Management.Automation.ItemNotFoundException] {
            if (-not $StampTenant) {
                $Tally.Total++
                $Tally.Failed++
            }
            throw
        } catch {
            $Tally.Total++
            $Tally.Failed++
            throw
        }
    }

    try {
        if ($ManualPagination) {
            $Body = Get-CIPPReportPage -TenantFilter $TenantFilter -Type 'DefenderIndicators' -PageSize ($Request.Query.PageSize -as [int]) -ContinuationToken $Request.Query.nextLink -Report $ReadIndicators
        } elseif ($TenantFilter -eq 'AllTenants') {
            $Body = [System.Collections.Generic.List[object]]::new()
            foreach ($Tenant in (Get-Tenants -IncludeErrors).defaultDomainName) {
                if (-not $Tenant) { continue }
                try {
                    foreach ($Indicator in (& $ReadIndicators $Tenant)) {
                        $Body.Add($Indicator)
                    }
                } catch [System.Management.Automation.ItemNotFoundException] {
                    continue
                } catch {
                    Write-LogMessage -API 'ListDefenderIndicators' -tenant $Tenant -message "Failed to read cached Defender indicators: $($_.Exception.Message)" -sev Warning
                }
            }
        } else {
            $Body = @(& $ReadIndicators $TenantFilter)
        }
        $StatusCode = Get-CippBulkStatusCode -Total $Tally.Total -Failed $Tally.Failed
        if ($StatusCode -eq [HttpStatusCode]::InternalServerError -and $ManualPagination -and $Body.Metadata.nextLink) {
            $StatusCode = [HttpStatusCode]::MultiStatus
        }
        if ($StatusCode -eq [HttpStatusCode]::InternalServerError) {
            $Body = @{ Results = 'Failed to read the cached Defender indicators for any tenant' }
        } elseif ($StatusCode -eq [HttpStatusCode]::MultiStatus -and $ManualPagination) {
            $Body.Metadata.FailedTenants = $Tally.Failed
        }
    } catch {
        $Body = @{ Results = Get-NormalizedError -Message $_.Exception.Message }
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
