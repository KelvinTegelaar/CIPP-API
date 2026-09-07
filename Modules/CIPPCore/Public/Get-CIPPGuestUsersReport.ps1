function Get-CIPPGuestUsersReport {
    <#
    .SYNOPSIS
        Reads cached guest users from the CIPP Reporting database

    .DESCRIPTION
        Returns the raw cached guest user objects for a tenant (or all tenants), with
        CacheTimestamp added, ready for the guest lifecycle classification in
        Invoke-ListGuestUsers.

    .PARAMETER TenantFilter
        The tenant to read cached guest users for, or 'AllTenants' for all tenants

    .PARAMETER PageSize
        When set, returns one page of at most this many rows as @{ Items; NextToken }, in table walk order.    .PARAMETER ContinuationToken
        NextToken from the previous page. Only meaningful together with PageSize.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [int]$PageSize,
        [string]$ContinuationToken
    )

    if ($PageSize -gt 0) {
        $Page = Get-CIPPDbItemPage -TenantFilter $TenantFilter -Type 'Guests' -PageSize $PageSize -ContinuationToken $ContinuationToken
        if ($TenantFilter -ne 'AllTenants' -and -not $ContinuationToken -and @($Page.Items).Count -eq 0 -and -not $Page.NextToken) {
            throw "No guest user data found in reporting database for $TenantFilter. Sync the report data first."
        }
        $Results = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Item in $Page.Items) {
            try {
                $Guest = $Item.Data | ConvertFrom-Json -Depth 10 -ErrorAction Stop
                # Per-item timestamp: a page may span tenants.
                $GuestProps = [ordered]@{ CacheTimestamp = $Item.Timestamp }
                if ($TenantFilter -eq 'AllTenants') {
                    $GuestProps['Tenant'] = $Item.PartitionKey
                }
                $Guest | Add-Member -NotePropertyMembers $GuestProps -Force
                $Results.Add($Guest)
            } catch {
                Write-LogMessage -API 'GuestUsersReport' -tenant $Item.PartitionKey -message "Failed to parse guest user item: $($_.Exception.Message)" -sev Warning
            }
        }
        return [PSCustomObject]@{
            Items     = $Results
            NextToken = $Page.NextToken
        }
    }

    if ($TenantFilter -eq 'AllTenants') {
        $AnyItems = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'Guests'
        $Tenants = @($AnyItems | Where-Object { $_.RowKey -notlike '*-Count' } | Select-Object -ExpandProperty PartitionKey -Unique)
        $TenantList = Get-Tenants -IncludeErrors
        $Tenants = $Tenants | Where-Object { $TenantList.defaultDomainName -contains $_ }

        $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Tenant in $Tenants) {
            try {
                $TenantResults = Get-CIPPGuestUsersReport -TenantFilter $Tenant
                foreach ($Result in $TenantResults) {
                    $Result | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Tenant -Force
                    $AllResults.Add($Result)
                }
            } catch {
                Write-LogMessage -API 'GuestUsersReport' -tenant $Tenant -message "Failed to get guest users report: $($_.Exception.Message)" -sev Warning
            }
        }
        return $AllResults
    }

    $Items = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'Guests' | Where-Object { $_.RowKey -notlike '*-Count' }
    if (-not $Items) {
        throw "No guest user data found in reporting database for $TenantFilter. Sync the report data first."
    }

    $CacheTimestamp = ($Items | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp

    $Results = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($Item in $Items) {
        try {
            $Guest = $Item.Data | ConvertFrom-Json -Depth 10 -ErrorAction Stop
            $Guest | Add-Member -NotePropertyName 'CacheTimestamp' -NotePropertyValue $CacheTimestamp -Force
            $Results.Add($Guest)
        } catch {
            Write-LogMessage -API 'GuestUsersReport' -tenant $TenantFilter -message "Failed to parse guest user item: $($_.Exception.Message)" -sev Warning
        }
    }

    return ($Results | Sort-Object displayName)
}
