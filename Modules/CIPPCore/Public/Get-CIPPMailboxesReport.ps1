function Get-CIPPMailboxesReport {
    <#
    .SYNOPSIS
        Generates a mailboxes report from the CIPP Reporting database

    .DESCRIPTION
        Retrieves mailbox data for a tenant from the reporting database

    .PARAMETER TenantFilter
        The tenant to generate the report for

    .PARAMETER PageSize
        When set, returns one page of at most this many rows as @{ Items; NextToken }, in table walk order.    .PARAMETER ContinuationToken
        NextToken from the previous page. Only meaningful together with PageSize.

    .EXAMPLE
        Get-CIPPMailboxesReport -TenantFilter 'contoso.onmicrosoft.com'
        Gets all mailboxes for the tenant from the report database
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [int]$PageSize,
        [string]$ContinuationToken
    )

    try {
        if ($PageSize -gt 0) {
            $Page = Get-CIPPDbItemPage -TenantFilter $TenantFilter -Type 'Mailboxes' -PageSize $PageSize -ContinuationToken $ContinuationToken
            if ($TenantFilter -ne 'AllTenants' -and -not $ContinuationToken -and @($Page.Items).Count -eq 0 -and -not $Page.NextToken) {
                throw 'No mailbox data found in reporting database. Sync the report data first.'
            }
            $Results = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($Item in $Page.Items) {
                $Mailbox = $Item.Data | ConvertFrom-Json
                # Per-item timestamp: a page may span tenants.
                $MailboxProps = [ordered]@{ CacheTimestamp = $Item.Timestamp }
                if ($TenantFilter -eq 'AllTenants') {
                    $MailboxProps['Tenant'] = $Item.PartitionKey
                }
                $Mailbox | Add-Member -NotePropertyMembers $MailboxProps -Force
                $Results.Add($Mailbox)
            }
            return [PSCustomObject]@{
                Items     = $Results
                NextToken = $Page.NextToken
            }
        }

        # Handle AllTenants
        if ($TenantFilter -eq 'AllTenants') {
            # Get all tenants that have mailbox data
            $AllMailboxItems = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'Mailboxes'
            $Tenants = @($AllMailboxItems | Where-Object { $_.RowKey -ne 'Mailboxes-Count' } | Select-Object -ExpandProperty PartitionKey -Unique)

            $TenantList = Get-Tenants -IncludeErrors
            $Tenants = $Tenants | Where-Object { $TenantList.defaultDomainName -contains $_ }

            $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($Tenant in $Tenants) {
                try {
                    $TenantResults = Get-CIPPMailboxesReport -TenantFilter $Tenant
                    foreach ($Result in $TenantResults) {
                        # Add Tenant property to each result
                        $Result | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Tenant -Force
                        $AllResults.Add($Result)
                    }
                } catch {
                    Write-LogMessage -API 'MailboxesReport' -tenant $Tenant -message "Failed to get report for tenant: $($_.Exception.Message)" -sev Warning
                }
            }
            return $AllResults
        }

        # Get mailboxes from reporting DB
        $MailboxItems = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'Mailboxes' | Where-Object { $_.RowKey -ne 'Mailboxes-Count' }
        if (-not $MailboxItems) {
            throw 'No mailbox data found in reporting database. Sync the report data first.'
        }

        # Get the most recent cache timestamp
        $CacheTimestamp = ($MailboxItems | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp

        # Parse mailbox data
        $AllMailboxes = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Item in $MailboxItems | Where-Object { $_.RowKey -ne 'Mailboxes-Count' }) {
            $Mailbox = $Item.Data | ConvertFrom-Json

            # Add cache timestamp
            $Mailbox | Add-Member -NotePropertyName 'CacheTimestamp' -NotePropertyValue $CacheTimestamp -Force

            $AllMailboxes.Add($Mailbox)
        }

        return $AllMailboxes | Sort-Object -Property displayName

    } catch {
        Write-LogMessage -API 'MailboxesReport' -tenant $TenantFilter -message "Failed to generate mailboxes report: $($_.Exception.Message)" -sev Error
        throw
    }
}
