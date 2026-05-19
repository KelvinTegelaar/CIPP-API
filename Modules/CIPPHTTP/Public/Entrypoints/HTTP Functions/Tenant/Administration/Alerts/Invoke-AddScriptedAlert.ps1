function Invoke-AddScriptedAlert {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Alert.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $tenantsJsonForStorage = $null

    if ($Request.Body.tenantFilter -is [array] -and @($Request.Body.tenantFilter).Count -eq 1) {
        $Request.Body | Add-Member -MemberType NoteProperty -Name 'tenantFilter' -Value $Request.Body.tenantFilter[0] -Force
    }

    if ($Request.Body.tenantFilter -is [array] -and @($Request.Body.tenantFilter).Count -gt 1) {
        try {
            $originalSelection = @($Request.Body.tenantFilter)
            $tenantsJsonForStorage = $originalSelection | ConvertTo-Json -Compress -Depth 10

            $hasAllTenants = @($originalSelection | Where-Object { $_.value -eq 'AllTenants' }).Count -gt 0

            if (-not $hasAllTenants) {
                $ExpandedSelection = Expand-CIPPTenantGroups -TenantFilter $originalSelection
                $targetDomains = @($ExpandedSelection | ForEach-Object { $_.value })

                $AllTenantsList = Get-Tenants -IncludeErrors
                $computedExcluded = @($AllTenantsList.defaultDomainName | Where-Object { $_ -notin $targetDomains })

                $existingExcluded = @()
                if ($Request.Body.PSObject.Properties['excludedTenants'] -and $Request.Body.excludedTenants) {
                    $existingExcluded = @($Request.Body.excludedTenants | ForEach-Object { $_.value ?? $_ })
                }
                $mergedExcluded = @($existingExcluded + $computedExcluded) | Where-Object { $_ } | Select-Object -Unique

                $excludedValue = @($mergedExcluded | ForEach-Object {
                        [PSCustomObject]@{ value = $_; label = $_ }
                    })
                $Request.Body | Add-Member -MemberType NoteProperty -Name 'excludedTenants' -Value $excludedValue -Force
            }

            if (-not $Request.Body.PSObject.Properties['RowKey'] -or -not $Request.Body.RowKey) {
                $Request.Body | Add-Member -MemberType NoteProperty -Name 'RowKey' -Value ((New-Guid).Guid) -Force
            }

            $tenantFilterValue = [PSCustomObject]@{
                value = 'AllTenants'
                label = '*All Tenants'
                type  = 'Tenant'
            }
            $Request.Body | Add-Member -MemberType NoteProperty -Name 'tenantFilter' -Value $tenantFilterValue -Force
        } catch {
            Write-Warning "Failed to process multi-tenant alert selection: $($_.Exception.Message)"
            $tenantsJsonForStorage = $null
        }
    }

    $ForwardRequest = @{
        Query   = @{ hidden = 'true' }
        Body    = $Request.Body
        Headers = $Request.Headers
    }
    $Response = Invoke-AddScheduledItem -Request $ForwardRequest -TriggerMetadata $TriggerMetadata

    if ($tenantsJsonForStorage) {
        try {
            $Table = Get-CIPPTable -TableName 'ScheduledTasks'
            $null = Update-AzDataTableEntity -Force @Table -Entity @{
                PartitionKey = 'ScheduledTask'
                RowKey       = [string]$Request.Body.RowKey
                Tenants      = [string]$tenantsJsonForStorage
            }
        } catch {
            Write-Warning "Failed to persist multi-tenant selection for alert: $($_.Exception.Message)"
        }
    }

    return $Response
}
