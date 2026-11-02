function Set-CIPPDBCacheOneDriveRootShortcuts {
    <#
    .SYNOPSIS
        Caches the SharePoint library shortcuts still sitting in each enabled member's OneDrive root

    .DESCRIPTION
        On demand only (no collection group): the MigrateOneDriveShortcuts baseline collects it on a
        miss and when it is older than 3 hours. Writes ONE summary row - offenders (sorted UPNs) and
        targets (one per shortcut to move) - so the baseline grades it declaratively. Root listings
        are batched through $batch; a user without a provisioned OneDrive (404) is skipped quietly.
        Nothing is written when every listing fails, so the previous verdict stands.

    .PARAMETER TenantFilter
        The tenant to cache shortcuts for

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
        $Users = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Users').Where({ $_ })
        if ($Users.Count -eq 0) {
            Set-CIPPDBCacheUsers -TenantFilter $TenantFilter
            $Users = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Users').Where({ $_ })
        }
        if ($Users.Count -eq 0) { throw 'the Users cache is empty' }

        $Candidates = @($Users.Where({ $_.accountEnabled -eq $true -and $_.userType -eq 'Member' -and $_.id -and -not [string]::IsNullOrWhiteSpace($_.userPrincipalName) }))
        $UpnById = @{}
        # ponytail: $top=999 keeps paging rare; $batch continuation pages drop the Prefer header, so a root over 999 items may miss shortcuts past page one.
        $Requests = foreach ($User in $Candidates) {
            $UpnById["$($User.id)"] = $User.userPrincipalName
            @{
                id      = "$($User.id)"
                method  = 'GET'
                url     = "users/$($User.id)/drive/root/children?`$select=id,name,remoteItem,parentReference&`$top=999"
                headers = @{ Prefer = 'Include-Feature=AddToOneDrive' }
            }
        }
        $Responses = if ($Candidates.Count -gt 0) { @(New-GraphBulkRequest -tenantid $TenantFilter -Requests @($Requests) -asapp $true) } else { @() }

        $Offenders = [System.Collections.Generic.List[string]]::new()
        $Targets = [System.Collections.Generic.List[object]]::new()
        $Failures = [System.Collections.Generic.List[string]]::new()
        $Readable = 0
        foreach ($Response in $Responses) {
            $Upn = $UpnById["$($Response.id)"]
            $Status = [int]$Response.status
            if ($Status -eq 404) { continue }
            $Readable++
            if ($Status -lt 200 -or $Status -gt 299) {
                $Failures.Add("$Upn -> $Status $($Response.body.error.message)")
                continue
            }
            $Shortcuts = @(@($Response.body.value).Where({ $_.remoteItem -and $_.parentReference.path -notmatch '/Shortcuts(/|$)' }))
            if ($Shortcuts.Count -eq 0) { continue }
            $Offenders.Add($Upn)
            foreach ($Shortcut in $Shortcuts) {
                $Targets.Add([PSCustomObject]@{ userId = "$($Response.id)"; userPrincipalName = $Upn; itemId = "$($Shortcut.id)"; name = "$($Shortcut.name)" })
            }
        }

        if ($Failures.Count -gt 0) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "OneDrive root shortcuts: could not list $($Failures.Count) of $Readable OneDrives. $($Failures.GetRange(0, [Math]::Min(10, $Failures.Count)) -join ' | ')" -sev Warning
            if ($Failures.Count -eq $Readable) { throw "every OneDrive listing failed: $($Failures[0])" }
        }

        $Offenders.Sort()
        $Summary = [PSCustomObject]@{ id = 'summary'; offenders = @($Offenders); targets = @($Targets) }
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'OneDriveRootShortcuts' -Data @($Summary) -AddCount
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache OneDrive root shortcuts: $($_.Exception.Message)" -sev Error
    }
}
