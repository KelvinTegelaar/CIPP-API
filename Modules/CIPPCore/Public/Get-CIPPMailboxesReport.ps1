function Get-CIPPMailboxesReport {
    <#
    .SYNOPSIS
        Generates a mailboxes report from the CIPP Reporting database

    .DESCRIPTION
        Retrieves mailbox data for a tenant from the reporting database. AllTenants reads are paged only.

    .PARAMETER TenantFilter
        The tenant to generate the report for

    .PARAMETER PageSize
        When set, returns one page of at most this many rows as @{ Items; NextToken }, in table walk order.
        Required for AllTenants.

    .PARAMETER ContinuationToken
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
                $Mailbox = [CIPP.CippJson]::ConvertFromJson($Item.Data)
                if ($null -eq $Mailbox) { continue }
                $Props = $Mailbox.PSObject.Properties
                # Per-item timestamp: a page may span tenants.
                $Props.Remove('CacheTimestamp'); $Props.Add([psnoteproperty]::new('CacheTimestamp', $Item.Timestamp))
                if ($TenantFilter -eq 'AllTenants') {
                    $Props.Remove('Tenant'); $Props.Add([psnoteproperty]::new('Tenant', $Item.PartitionKey))
                }
                $Results.Add($Mailbox)
            }
            return [PSCustomObject]@{
                Items     = $Results
                NextToken = $Page.NextToken
            }
        }

        if ($TenantFilter -eq 'AllTenants') {
            throw [System.ArgumentException]::new('AllTenants mailbox reads are paged: pass -PageSize.')
        }

        $CacheTimestamp = $null
        $AllMailboxes = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Item in @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'Mailboxes')) {
            if ($Item.RowKey -eq 'Mailboxes-Count') { continue }
            if ($Item.Timestamp -and (-not $CacheTimestamp -or $Item.Timestamp -gt $CacheTimestamp)) { $CacheTimestamp = $Item.Timestamp }
            $Mailbox = [CIPP.CippJson]::ConvertFromJson($Item.Data)
            if ($null -ne $Mailbox) { $AllMailboxes.Add($Mailbox) }
        }
        if ($AllMailboxes.Count -eq 0) {
            throw 'No mailbox data found in reporting database. Sync the report data first.'
        }

        foreach ($Mailbox in $AllMailboxes) {
            $Props = $Mailbox.PSObject.Properties
            $Props.Remove('CacheTimestamp'); $Props.Add([psnoteproperty]::new('CacheTimestamp', $CacheTimestamp))
        }

        return $AllMailboxes | Sort-Object -Property displayName

    } catch {
        Write-LogMessage -API 'MailboxesReport' -tenant $TenantFilter -message "Failed to generate mailboxes report: $($_.Exception.Message)" -sev Error
        throw
    }
}
