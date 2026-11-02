function Set-CIPPDBCacheOneDriveQuotas {
    <#
    .SYNOPSIS
        Caches the OneDrive storage quota of every enabled, licensed user

    .DESCRIPTION
        On-demand only (not part of a scheduled collection group): the OneDriveLicensedQuota baseline
        collects it on miss, refreshes it when older than 3 hours and again after it raises quotas.
        One row per provisioned drive, keyed by the owner's user id. Users come from the Users cache;
        drives are read app-only through Graph $batch. A user without a provisioned OneDrive has no row.

    .PARAMETER TenantFilter
        The tenant to cache OneDrive quotas for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching OneDrive quotas' -sev Debug

        $AllUsers = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Users' -Fields 'id', 'userPrincipalName', 'accountEnabled', 'assignedLicenses')
        # No Users cache yet: write nothing, so this does not read as collected-and-empty.
        if ($AllUsers.Count -eq 0) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Skipped OneDrive quota cache: the Users cache is empty' -sev Warning
            return
        }

        $UpnById = @{}
        foreach ($User in $AllUsers) {
            if ($User.id -and $User.accountEnabled -eq $true -and @($User.assignedLicenses).Count -gt 0) { $UpnById["$($User.id)"] = "$($User.userPrincipalName)" }
        }

        $Rows = [System.Collections.Generic.List[object]]::new()
        $Failures = [System.Collections.Generic.List[string]]::new()
        $Readable = 0
        if ($UpnById.Count -gt 0) {
            $Requests = foreach ($Id in $UpnById.Keys) { @{ id = $Id; method = 'GET'; url = "users/$Id/drive?`$select=quota,webUrl" } }
            foreach ($Response in @(New-GraphBulkRequest -tenantid $TenantFilter -Requests @($Requests) -asapp $true)) {
                # 404 is a OneDrive that has not been provisioned yet, not a failed read.
                if ($Response.status -eq 404) { continue }
                $Readable++
                if ($Response.status -ne 200) {
                    $Failures.Add("$($UpnById["$($Response.id)"]) -> $($Response.status) $($Response.body.error.message)")
                    continue
                }
                $Rows.Add([PSCustomObject]@{
                        id                = "$($Response.id)"
                        userPrincipalName = $UpnById["$($Response.id)"]
                        quotaTotal        = [int64]($Response.body.quota.total ?? 0)
                        webUrl            = "$($Response.body.webUrl)"
                    })
            }
        }

        if ($Failures.Count -gt 0) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "OneDrive quotas: could not read $($Failures.Count) of $Readable OneDrives. $($Failures.GetRange(0, [Math]::Min(10, $Failures.Count)) -join ' | ')" -sev Warning
            # An empty set would grade every OneDrive compliant; keep the previous cache instead.
            if ($Failures.Count -eq $Readable) { throw "every OneDrive quota read failed: $($Failures[0])" }
        }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'OneDriveQuotas' -Data @($Rows) -AddCount -ClearOnEmpty
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Rows.Count) OneDrive quotas" -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache OneDrive quotas: $($_.Exception.Message)" -sev Error
        throw
    }
}
