function Invoke-ListDefenderMachines {
    <#
    .FUNCTIONALITY
        Entrypoint,TenantGroup
    .ROLE
        Security.Defender.Read
    .DESCRIPTION
        Lists the cached Microsoft Defender for Endpoint device inventory for a tenant, including devices onboarded without Intune: sensor health, onboarding status, risk and exposure, last report time and antivirus health where Defender supplies it. Always reads the reporting database cache. AllTenants returns the devices of the caller's permitted tenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter

    if (-not $TenantFilter) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'tenantFilter is required' }
            })
    }

    $Tally = @{ Total = 0; Failed = 0 }
    $ReadDevices = {
        param($Tenant)
        try {
            $Rows = @(if ($TenantFilter -eq 'AllTenants') {
                    Get-CIPPDbItem -Partition $Tenant -Type 'DefenderMachines'
                } else {
                    Get-CIPPDbItem -TenantFilter $Tenant -Type 'DefenderMachines'
                })
            if ($Rows.Count -eq 0) {
                throw [System.Management.Automation.ItemNotFoundException]::new("No Defender devices cached for $Tenant. Sync the report data first.")
            }
            $Count = $null
            $Devices = @(foreach ($Row in $Rows) {
                    if ($Row.RowKey -eq 'DefenderMachines-Count') {
                        $Count = [int]$Row.DataCount
                        continue
                    }
                    $Device = [CIPP.CippJson]::ConvertFromJson($Row.Data, $null)
                    if ($Device -isnot [pscustomobject] -or -not $Device.id) { throw "A cached Defender device row for $Tenant could not be read" }
                    $Device.PSObject.Properties.Add([psnoteproperty]::new('CacheTimestamp', $Row.Timestamp))
                    $Device
                })
            if ($null -eq $Count -or ($Count -gt 0 -and $Devices.Count -eq 0)) { throw "The Defender device cache for $Tenant is incomplete. Sync the report data again." }
            $Tally.Total++
            $Devices
        } catch [System.Management.Automation.ItemNotFoundException] {
            throw
        } catch {
            $Tally.Total++
            $Tally.Failed++
            throw
        }
    }

    try {
        if ($Request.Query.manualPagination -eq $true) {
            $Body = Get-CIPPReportPage -TenantFilter $TenantFilter -Type 'DefenderMachines' -PageSize ($Request.Query.PageSize -as [int]) -ContinuationToken $Request.Query.nextLink -Report $ReadDevices
        } elseif ($TenantFilter -eq 'AllTenants') {
            $Body = [System.Collections.Generic.List[object]]::new()
            foreach ($Tenant in (Get-Tenants -IncludeErrors).defaultDomainName) {
                if (-not $Tenant) { continue }
                try {
                    foreach ($Device in (& $ReadDevices $Tenant)) {
                        $Device.PSObject.Properties.Add([psnoteproperty]::new('Tenant', $Tenant))
                        $Body.Add($Device)
                    }
                } catch [System.Management.Automation.ItemNotFoundException] {
                    continue
                } catch {
                    Write-LogMessage -API 'ListDefenderMachines' -tenant $Tenant -message "Failed to read cached Defender devices: $($_.Exception.Message)" -sev Warning
                }
            }
        } else {
            $Body = @(& $ReadDevices $TenantFilter)
        }
        $StatusCode = Get-CippBulkStatusCode -Total $Tally.Total -Failed $Tally.Failed
        if ($StatusCode -eq [HttpStatusCode]::InternalServerError) {
            $Body = @{ Results = 'Failed to read the cached Defender devices for any tenant' }
        } elseif ($StatusCode -eq [HttpStatusCode]::MultiStatus -and $Request.Query.manualPagination -eq $true) {
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
