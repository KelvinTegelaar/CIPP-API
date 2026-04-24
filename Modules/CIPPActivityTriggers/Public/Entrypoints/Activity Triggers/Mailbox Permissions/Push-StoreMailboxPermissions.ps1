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
        $AllSendOnBehalfPermissions = [System.Collections.Generic.List[object]]::new()
        $AllCalendarPermissions = [System.Collections.Generic.List[object]]::new()

        foreach ($BatchResult in $Results) {
            # Activity functions may return an array [hashtable, "status message"]
            # Extract the actual hashtable if result is an array
            $ActualResult = $BatchResult
            if ($BatchResult -is [array] -and $BatchResult.Count -gt 0) {
                Write-Information "Result is array with $($BatchResult.Count) elements, extracting first element"
                $ActualResult = $BatchResult[0]
            }

            if ($ActualResult -and ($ActualResult -is [hashtable] -or $ActualResult -is [System.Collections.IDictionary])) {
                Write-Information "Processing hashtable result with keys: $($ActualResult.Keys -join ', ')"
                # Results are grouped by cmdlet name due to ReturnWithCommand
                if ($ActualResult['Get-MailboxPermission']) {
                    $MailboxPerms = @($ActualResult['Get-MailboxPermission'])
                    Write-Information "Adding $($MailboxPerms.Count) mailbox permissions"
                    $AllMailboxPermissions.AddRange($MailboxPerms)
                }
                if ($ActualResult['Get-RecipientPermission']) {
                    $RecipientPerms = @($ActualResult['Get-RecipientPermission'])
                    Write-Information "Adding $($RecipientPerms.Count) recipient permissions"
                    $AllRecipientPermissions.AddRange($RecipientPerms)
                }
                if ($ActualResult['Get-Mailbox']) {
                    $SendOnBehalfRows = @($ActualResult['Get-Mailbox'])
                    Write-Information "Adding $($SendOnBehalfRows.Count) send-on-behalf permissions"
                    $AllSendOnBehalfPermissions.AddRange($SendOnBehalfRows)
                }
                if ($ActualResult['Get-MailboxFolderPermission']) {
                    $CalendarPerms = @($ActualResult['Get-MailboxFolderPermission'])
                    Write-Information "Adding $($CalendarPerms.Count) calendar permissions"
                    $AllCalendarPermissions.AddRange($CalendarPerms)
                }
            } else {
                Write-Information "Skipping non-hashtable result: $($ActualResult.GetType().Name)"
            }
        }

        # Combine all permissions (mailbox and recipient) into a single collection
        $AllPermissions = [System.Collections.Generic.List[object]]::new()
        $AllPermissions.AddRange($AllMailboxPermissions)
        $AllPermissions.AddRange($AllRecipientPermissions)
        $AllPermissions.AddRange($AllSendOnBehalfPermissions)

        Write-Information "Aggregated $($AllPermissions.Count) total permissions ($($AllMailboxPermissions.Count) mailbox + $($AllRecipientPermissions.Count) recipient + $($AllSendOnBehalfPermissions.Count) send-on-behalf)"
        Write-Information "Aggregated $($AllCalendarPermissions.Count) calendar permissions"

        # Store all permissions together as MailboxPermissions
        if ($AllPermissions.Count -gt 0) {
            $AllPermissions | Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'MailboxPermissions' -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($AllPermissions.Count) mailbox permission records" -sev Info
        } else {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'No mailbox permissions found to cache' -sev Info
        }

        # Store calendar permissions separately
        if ($AllCalendarPermissions.Count -gt 0) {
            $AllCalendarPermissions | Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CalendarPermissions' -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($AllCalendarPermissions.Count) calendar permission records" -sev Info
        } else {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'No calendar permissions found to cache' -sev Info
        }

        return

    } catch {
        $ErrorMsg = "Failed to store mailbox permissions for tenant $TenantFilter : $($_.Exception.Message)"
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message $ErrorMsg -sev Error
        throw $ErrorMsg
    }
}
