function Get-CIPPSharedMailboxAccountEnabledReport {
    <#
    .SYNOPSIS
        Generates the "shared mailbox with enabled account" report from the CIPP Reporting database

    .DESCRIPTION
        Reproduces the live Invoke-ListSharedMailboxAccountEnabled payload entirely from cached data,
        joining the cached 'Mailboxes' dataset (to identify SharedMailbox recipients) with the cached
        'Users' dataset (for accountEnabled / assignedLicenses / onPremisesSyncEnabled) by UPN. Only
        shared mailboxes whose user account is enabled are returned. No dedicated cache writer is needed —
        both source datasets are already populated on the scheduled cache cycle.

    .PARAMETER TenantFilter
        The tenant to generate the report for. 'AllTenants' fans out across every tenant present in the
        Mailboxes cache.

    .EXAMPLE
        Get-CIPPSharedMailboxAccountEnabledReport -TenantFilter 'contoso.onmicrosoft.com'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        # Handle AllTenants by recursing per tenant present in the Mailboxes cache
        if ($TenantFilter -eq 'AllTenants') {
            $AllMailboxItems = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'Mailboxes'
            $Tenants = @($AllMailboxItems | Where-Object { $_.RowKey -ne 'Mailboxes-Count' } | Select-Object -ExpandProperty PartitionKey -Unique)

            $TenantList = Get-Tenants -IncludeErrors
            $Tenants = $Tenants | Where-Object { $TenantList.defaultDomainName -contains $_ }

            $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($Tenant in $Tenants) {
                try {
                    $TenantResults = Get-CIPPSharedMailboxAccountEnabledReport -TenantFilter $Tenant
                    foreach ($Result in $TenantResults) {
                        $Result | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Tenant -Force
                        $AllResults.Add($Result)
                    }
                } catch {
                    Write-LogMessage -API 'SharedMailboxAccountEnabledReport' -tenant $Tenant -message "Failed to get report for tenant: $($_.Exception.Message)" -sev Warning
                }
            }
            return $AllResults
        }

        # Mailboxes cache identifies which mailboxes are shared (recipientTypeDetails) and the join key (UPN)
        $MailboxItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'Mailboxes' | Where-Object { $_.RowKey -ne 'Mailboxes-Count' }
        if (-not $MailboxItems) {
            throw 'No mailbox data found in reporting database. Sync the report data first.'
        }

        # Users cache carries the account/license fields the live endpoint pulls from Graph /users
        $UserItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'Users' | Where-Object { $_.RowKey -ne 'Users-Count' }

        # Most-recent cache timestamp across both source datasets
        $CacheTimestamp = (@($MailboxItems) + @($UserItems) | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp

        # Build a UPN -> user lookup (hashtable string keys are case-insensitive, matching UPN semantics)
        $UserByUPN = @{}
        foreach ($Item in $UserItems) {
            $User = $Item.Data | ConvertFrom-Json
            if ($User.userPrincipalName) {
                $UserByUPN[$User.userPrincipalName] = $User
            }
        }

        $Results = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Item in $MailboxItems) {
            $Mailbox = $Item.Data | ConvertFrom-Json
            if ($Mailbox.recipientTypeDetails -ne 'SharedMailbox') { continue }

            $User = $UserByUPN[$Mailbox.UPN]
            if (-not $User -or -not $User.accountEnabled) { continue }

            # Match the live Invoke-ListSharedMailboxAccountEnabled shape exactly. 'id' must be the user's
            # object id — the page's "Block Sign In" action posts it to ExecDisableUser.
            $Results.Add([PSCustomObject]@{
                    UserPrincipalName     = $User.userPrincipalName
                    displayName           = $User.displayName
                    givenName             = $User.givenName
                    surname               = $User.surname
                    accountEnabled        = $User.accountEnabled
                    assignedLicenses      = $User.assignedLicenses
                    id                    = $User.id
                    onPremisesSyncEnabled = $User.onPremisesSyncEnabled
                    CacheTimestamp        = $CacheTimestamp
                })
        }

        return $Results

    } catch {
        Write-LogMessage -API 'SharedMailboxAccountEnabledReport' -tenant $TenantFilter -message "Failed to generate shared mailbox account enabled report: $($_.Exception.Message)" -sev Error
        throw
    }
}
