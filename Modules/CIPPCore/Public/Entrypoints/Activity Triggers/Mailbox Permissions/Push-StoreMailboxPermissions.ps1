function Push-StoreMailboxPermissions {
    <#
    .SYNOPSIS
        Post-execution function to aggregate and store all mailbox and calendar permissions

    .DESCRIPTION
        Collects results from all batches and stores them in the reporting database

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $TenantFilter = $Item.Parameters.TenantFilter
    $Results = $Item.Results

    try {
        Write-Information "Storing mailbox and calendar permissions for tenant $TenantFilter"
        Write-Information "Received $($Results.Count) batch results"

        # Log each result for debugging
        for ($i = 0; $i -lt $Results.Count; $i++) {
            $result = $Results[$i]
            Write-Information "Result $i type: $($result.GetType().Name), value: $($result | ConvertTo-Json -Depth 2 -Compress)"
        }

        # Aggregate results by command type from all batches
        $AllMailboxPermissions = [System.Collections.Generic.List[object]]::new()
        $AllRecipientPermissions = [System.Collections.Generic.List[object]]::new()
        $AllCalendarPermissions = [System.Collections.Generic.List[object]]::new()

        foreach ($BatchResult in $Results) {
            # Activity functions may return an array [hashtable, "status message"]
            # Extract the actual hashtable if result is an array
            $ActualResult = $BatchResult
            if ($BatchResult -is [array] -and $BatchResult.Count -gt 0) {
                Write-Information "Result is array with $($BatchResult.Count) elements, extracting first element"
                $ActualResult = $BatchResult[0]
            }

            if ($ActualResult -and $ActualResult -is [hashtable]) {
                Write-Information "Processing hashtable result with keys: $($ActualResult.Keys -join ', ')"
                # Results are grouped by cmdlet name due to ReturnWithCommand
                if ($ActualResult['Get-MailboxPermission']) {
                    Write-Information "Adding $($ActualResult['Get-MailboxPermission'].Count) mailbox permissions"
                    foreach ($perm in $ActualResult['Get-MailboxPermission']) {
                        $AllMailboxPermissions.Add($perm)
                    }
                }
                if ($ActualResult['Get-RecipientPermission']) {
                    Write-Information "Adding $($ActualResult['Get-RecipientPermission'].Count) recipient permissions"
                    foreach ($perm in $ActualResult['Get-RecipientPermission']) {
                        $AllRecipientPermissions.Add($perm)
                    }
                }
                if ($ActualResult['Get-MailboxFolderPermission']) {
                    Write-Information "Adding $($ActualResult['Get-MailboxFolderPermission'].Count) calendar permissions"
                    foreach ($perm in $ActualResult['Get-MailboxFolderPermission']) {
                        $AllCalendarPermissions.Add($perm)
                    }
                }
            } else {
                Write-Information "Skipping non-hashtable result: $($ActualResult.GetType().Name)"
            }
        }

        # Combine all permissions (mailbox and recipient) into a single collection
        $AllPermissions = [System.Collections.Generic.List[object]]::new()
        foreach ($perm in $AllMailboxPermissions) {
            $AllPermissions.Add($perm)
        }
        foreach ($perm in $AllRecipientPermissions) {
            $AllPermissions.Add($perm)
        }

        Write-Information "Aggregated $($AllPermissions.Count) total permissions ($($AllMailboxPermissions.Count) mailbox + $($AllRecipientPermissions.Count) recipient)"
        Write-Information "Aggregated $($AllCalendarPermissions.Count) calendar permissions"

        # Store all permissions together as MailboxPermissions
        if ($AllPermissions.Count -gt 0) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'MailboxPermissions' -Data $AllPermissions.ToArray()
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'MailboxPermissions' -Data @{ Count = $AllPermissions.Count } -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($AllPermissions.Count) mailbox permission records" -sev Info
        } else {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'No mailbox permissions found to cache' -sev Info
        }

        # Clear to free memory before processing calendar permissions
        $AllMailboxPermissions.Clear()
        $AllRecipientPermissions.Clear()
        $AllPermissions.Clear()
        $AllMailboxPermissions = $null
        $AllRecipientPermissions = $null
        $AllPermissions = $null

        # Store calendar permissions separately
        if ($AllCalendarPermissions.Count -gt 0) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CalendarPermissions' -Data $AllCalendarPermissions.ToArray()
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CalendarPermissions' -Data @{ Count = $AllCalendarPermissions.Count } -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($AllCalendarPermissions.Count) calendar permission records" -sev Info
        } else {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'No calendar permissions found to cache' -sev Info
        }

        # Final cleanup
        $AllCalendarPermissions.Clear()
        $AllCalendarPermissions = $null
        [System.GC]::Collect()

        return

    } catch {
        $ErrorMsg = "Failed to store mailbox permissions for tenant $TenantFilter : $($_.Exception.Message)"
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message $ErrorMsg -sev Error
        throw $ErrorMsg
    }
}
