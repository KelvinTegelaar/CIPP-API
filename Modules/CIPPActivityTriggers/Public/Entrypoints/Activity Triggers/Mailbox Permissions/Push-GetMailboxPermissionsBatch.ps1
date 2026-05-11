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
    $MailboxData = @($Item.MailboxData)
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
                $AccessStr = if ($Perm.AccessRights -is [array]) { $Perm.AccessRights -join ',' } else { $Perm.AccessRights }
                [PSCustomObject]@{
                    id           = "MBP-$($Perm.Identity)-$($Perm.User)-$AccessStr"
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
                $UserVal = if ($Perm.Trustee) { $Perm.Trustee } else { $Perm.User }
                $AccessStr = if ($Perm.AccessRights -is [array]) { $Perm.AccessRights -join ',' } else { $Perm.AccessRights }
                [PSCustomObject]@{
                    id           = "RCP-$($Perm.Identity)-$UserVal-$AccessStr"
                    Identity     = $Perm.Identity
                    User         = $UserVal
                    AccessRights = $Perm.AccessRights
                    IsInherited  = $Perm.IsInherited
                    Deny         = $Perm.Deny
                }
            }
            $MailboxPermissions['Get-RecipientPermission'] = $NormalizedRecipientPerms
        }

        $MailboxIdentityLookup = @{}
        foreach ($MappedMailbox in ($MailboxData | Where-Object { $_.Id -and $_.UPN })) {
            $MailboxIdentityLookup[[string]$MappedMailbox.Id] = [string]$MappedMailbox.UPN
        }

        # Normalize SendOnBehalf permissions from passed mailbox metadata
        $NormalizedSendOnBehalfPerms = foreach ($Mailbox in ($MailboxData | Where-Object { $_.GrantSendOnBehalfTo -and ($Mailboxes -contains $_.UPN) })) {
            foreach ($Delegate in (@($Mailbox.GrantSendOnBehalfTo) | Where-Object { $_ -and $MailboxIdentityLookup.ContainsKey([string]$_) })) {
                $DelegateUPN = $MailboxIdentityLookup[[string]$Delegate]
                [PSCustomObject]@{
                    id           = "SOB-$($Mailbox.UPN)-$DelegateUPN"
                    Identity     = $Mailbox.UPN
                    User         = $DelegateUPN
                    AccessRights = @('SendOnBehalf')
                    IsInherited  = $false
                    Deny         = $false
                }
            }
        }
        $MailboxPermissions['Get-Mailbox'] = @($NormalizedSendOnBehalfPerms)

        $MailboxPermCount = if ($MailboxPermissions['Get-MailboxPermission']) { $MailboxPermissions['Get-MailboxPermission'].Count } else { 0 }
        $RecipientPermCount = if ($MailboxPermissions['Get-RecipientPermission']) { $MailboxPermissions['Get-RecipientPermission'].Count } else { 0 }
        $SendOnBehalfPermCount = if ($MailboxPermissions['Get-Mailbox']) { $MailboxPermissions['Get-Mailbox'].Count } else { 0 }

        Write-Information "Completed batch $BatchNumber of $TotalBatches - processed $($Mailboxes.Count) mailboxes: $MailboxPermCount mailbox permissions, $RecipientPermCount recipient permissions, $SendOnBehalfPermCount send-on-behalf permissions"

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
