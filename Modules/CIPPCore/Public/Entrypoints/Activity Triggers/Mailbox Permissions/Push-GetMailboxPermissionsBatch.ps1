function Push-GetMailboxPermissionsBatch {
    <#
    .SYNOPSIS
        Process a batch of mailbox permission queries

    .DESCRIPTION
        Queries mailbox permissions for a batch of mailboxes and stores in the reporting database

    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $TenantFilter = $Item.TenantFilter
    $Mailboxes = $Item.Mailboxes
    $BatchNumber = $Item.BatchNumber
    $TotalBatches = $Item.TotalBatches

    try {
        Write-Information "Processing batch $BatchNumber of $TotalBatches for tenant $TenantFilter with $($Mailboxes.Count) mailboxes"
        Write-Information "Mailbox UPNs in batch: $($Mailboxes -join ', ')"

        # Build bulk requests for this batch (2 queries per mailbox: MailboxPermission + RecipientPermission)
        # Calendar permissions require locale-specific folder names and will be collected separately if needed
        $ExoBulkRequests = foreach ($MailboxUPN in $Mailboxes) {
            @{
                CmdletInput = @{
                    CmdletName = 'Get-MailboxPermission'
                    Parameters = @{ Identity = $MailboxUPN }
                }
            }
            @{
                CmdletInput = @{
                    CmdletName = 'Get-RecipientPermission'
                    Parameters = @{ Identity = $MailboxUPN }
                }
            }
        }

        Write-Information "Built $($ExoBulkRequests.Count) bulk requests for batch $BatchNumber"

        # Execute bulk request for this batch with ReturnWithCommand to separate permission types
        $MailboxPermissions = New-ExoBulkRequest -cmdletArray @($ExoBulkRequests) -tenantid $TenantFilter -ReturnWithCommand $true

        Write-Information "Bulk request completed. Result type: $($MailboxPermissions.GetType().Name)"
        if ($MailboxPermissions -is [hashtable]) {
            Write-Information "Result keys: $($MailboxPermissions.Keys -join ', ')"
            if ($MailboxPermissions['Get-MailboxPermission']) {
                Write-Information "Sample MailboxPermission: $($MailboxPermissions['Get-MailboxPermission'][0] | ConvertTo-Json -Depth 2 -Compress)"
            }
            if ($MailboxPermissions['Get-RecipientPermission']) {
                Write-Information "Sample RecipientPermission: $($MailboxPermissions['Get-RecipientPermission'][0] | ConvertTo-Json -Depth 2 -Compress)"
            }
        }

        # Normalize MailboxPermission results
        if ($MailboxPermissions['Get-MailboxPermission']) {
            $NormalizedMailboxPerms = foreach ($Perm in $MailboxPermissions['Get-MailboxPermission']) {
                # Create normalized object with consistent property names and unique ID
                [PSCustomObject]@{
                    id           = [guid]::NewGuid().ToString()
                    Identity     = $Perm.Identity
                    User         = $Perm.User
                    AccessRights = $Perm.AccessRights
                    IsInherited  = $Perm.IsInherited
                    Deny         = $Perm.Deny
                }
            }
            $MailboxPermissions['Get-MailboxPermission'] = $NormalizedMailboxPerms
        }

        # Normalize the results - RecipientPermission uses 'Trustee' instead of 'User'
        if ($MailboxPermissions['Get-RecipientPermission']) {
            $NormalizedRecipientPerms = foreach ($Perm in $MailboxPermissions['Get-RecipientPermission']) {
                # Create normalized object with consistent property names and unique ID
                [PSCustomObject]@{
                    id           = [guid]::NewGuid().ToString()
                    Identity     = $Perm.Identity
                    User         = if ($Perm.Trustee) { $Perm.Trustee } else { $Perm.User }
                    AccessRights = $Perm.AccessRights
                    IsInherited  = $Perm.IsInherited
                    Deny         = $Perm.Deny
                }
            }
            $MailboxPermissions['Get-RecipientPermission'] = $NormalizedRecipientPerms
        }

        $MailboxPermCount = if ($MailboxPermissions['Get-MailboxPermission']) { $MailboxPermissions['Get-MailboxPermission'].Count } else { 0 }
        $RecipientPermCount = if ($MailboxPermissions['Get-RecipientPermission']) { $MailboxPermissions['Get-RecipientPermission'].Count } else { 0 }

        Write-Information "Completed batch $BatchNumber of $TotalBatches - processed $($Mailboxes.Count) mailboxes: $MailboxPermCount mailbox permissions, $RecipientPermCount recipient permissions"

        # Return results to be aggregated by post-execution function
        return $MailboxPermissions

    } catch {
        $ErrorMsg = "Failed to process batch $BatchNumber of $TotalBatches for tenant $TenantFilter : $($_.Exception.Message)"
        Write-Information "ERROR in Push-GetMailboxPermissionsBatch: $ErrorMsg"
        Write-Information "Stack trace: $($_.ScriptStackTrace)"
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message $ErrorMsg -sev Error
        throw $ErrorMsg
    }
}
