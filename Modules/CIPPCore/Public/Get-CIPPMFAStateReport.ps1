function Get-CIPPMFAStateReport {
    <#
    .SYNOPSIS
        Generates an MFA state report from the CIPP Reporting database

    .DESCRIPTION
        Retrieves MFA state data for a tenant from the reporting database.

        This function is the peak-allocation point of the MFA report: a 60k user tenant
        used to grow the worker by ~1.3 GB for a single request. Four things keep that
        down and should not be undone casually:

        * Rows are released as they are consumed, so the raw table entities and their
          JSON blobs are not all rooted at once alongside the results.
        * ConvertFrom-Json -AsHashtable is used instead of the default PSCustomObject.
          The emitted JSON is byte for byte identical, but the retained form is roughly
          half the size and materially cheaper to serialise.
        * Nothing is added to the deserialised object after the fact. Adding a property
          to a ConvertFrom-Json result (Add-Member, or PSObject.Properties.Add) forces
          PowerShell to materialise a full property bag per row, which was previously
          the single largest allocation here.
        * The DisplayName sort extracts keys once and uses Array::Sort. Sort-Object
          -Property against a dictionary resolves the key through the member adapter on
          every comparison and is several times slower than the sort it replaces.

    .PARAMETER TenantFilter
        The tenant to generate the report for

    .PARAMETER PageSize
        When set, returns one page of at most this many rows as @{ Items; NextToken }, in table walk order.    .PARAMETER ContinuationToken
        NextToken from the previous page. Only meaningful together with PageSize.

    .EXAMPLE
        Get-CIPPMFAStateReport -TenantFilter 'contoso.onmicrosoft.com'
        Gets MFA state for all users in the tenant
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
            $Page = Get-CIPPDbItemPage -TenantFilter $TenantFilter -Type 'MFAState' -PageSize $PageSize -ContinuationToken $ContinuationToken
            if ($TenantFilter -ne 'AllTenants' -and -not $ContinuationToken -and @($Page.Items).Count -eq 0 -and -not $Page.NextToken) {
                throw 'No MFA state data found in reporting database. Sync the report data first.'
            }
            # Same memory discipline as the unpaged path below: hashtables, no Add-Member.
            $Results = [System.Collections.Generic.List[object]]::new()
            foreach ($Item in $Page.Items) {
                $MFAUser = $Item.Data | ConvertFrom-Json -AsHashtable

                # Legacy rows stored these as embedded JSON strings rather than as objects.
                if ($MFAUser['CAPolicies'] -is [string]) {
                    $MFAUser['CAPolicies'] = try { $MFAUser['CAPolicies'] | ConvertFrom-Json -AsHashtable } catch { $MFAUser['CAPolicies'] }
                }
                if ($MFAUser['MFAMethods'] -is [string]) {
                    $MFAUser['MFAMethods'] = try { $MFAUser['MFAMethods'] | ConvertFrom-Json -AsHashtable } catch { $MFAUser['MFAMethods'] }
                }

                $MFAUser['CacheTimestamp'] = $Item.Timestamp
                # Tenant is already stored on every row by Get-CIPPMFAState; only fill it
                # in for older rows that predate that.
                if (-not $MFAUser['Tenant']) { $MFAUser['Tenant'] = $Item.PartitionKey }
                $Results.Add($MFAUser)
            }
            return [PSCustomObject]@{
                Items     = $Results
                NextToken = $Page.NextToken
            }
        }

        # Handle AllTenants
        if ($TenantFilter -eq 'AllTenants') {
            # Enumerate tenants from the per-type count rows. Reading every user row of
            # every tenant just to collect the distinct partition keys pulled the entire
            # multi-tenant dataset into memory and then threw it away.
            $CountRows = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'MFAState' -CountsOnly
            $TenantList = Get-Tenants -IncludeErrors
            $KnownTenants = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($Known in $TenantList.defaultDomainName) {
                if ($Known) { $null = $KnownTenants.Add([string]$Known) }
            }

            $Tenants = [System.Collections.Generic.List[string]]::new()
            foreach ($Row in $CountRows) {
                $Partition = [string]$Row.PartitionKey
                if ($Partition -and $KnownTenants.Contains($Partition) -and -not $Tenants.Contains($Partition)) {
                    $Tenants.Add($Partition)
                }
            }

            $AllResults = [System.Collections.Generic.List[object]]::new()
            foreach ($Tenant in $Tenants) {
                try {
                    foreach ($Result in (Get-CIPPMFAStateReport -TenantFilter $Tenant)) {
                        # Tenant is already stored on every row by Get-CIPPMFAState; only
                        # fill it in for older rows that predate that.
                        if (-not $Result['Tenant']) { $Result['Tenant'] = $Tenant }
                        $AllResults.Add($Result)
                    }
                } catch {
                    Write-LogMessage -API 'MFAStateReport' -tenant $Tenant -message "Failed to get report for tenant: $($_.Exception.Message)" -sev Warning
                }
            }
            return $AllResults
        }

        # Get MFA state from reporting DB. The count row is filtered inside the projection
        # loop below rather than in a separate pass over every row.
        $MFAItems = @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'MFAState')

        # Most recent cache timestamp, in a single pass. Sorting every row just to take
        # the first one was about a second of pure overhead on a large tenant.
        #
        # The count row is deliberately excluded: Add-CIPPDbItem writes it last, so it
        # carries a timestamp a little later than any data row and would otherwise report
        # a cache time that no user row actually has.
        $CacheTimestamp = $null
        foreach ($Item in $MFAItems) {
            if ($Item.RowKey -eq 'MFAState-Count') { continue }
            $Stamp = $Item.Timestamp
            if ($Stamp -and ($null -eq $CacheTimestamp -or $Stamp -gt $CacheTimestamp)) {
                $CacheTimestamp = $Stamp
            }
        }

        $AllMFAState = [System.Collections.Generic.List[object]]::new($MFAItems.Count)
        for ($i = 0; $i -lt $MFAItems.Count; $i++) {
            $Item = $MFAItems[$i]
            # Drop the reference as we go so the entity and its JSON blob become
            # collectable while the rest of the set is still being built.
            $MFAItems[$i] = $null
            if ($null -eq $Item -or $Item.RowKey -eq 'MFAState-Count') { continue }

            $MFAUser = $Item.Data | ConvertFrom-Json -AsHashtable

            # Legacy rows stored these as embedded JSON strings rather than as objects.
            if ($MFAUser['CAPolicies'] -is [string]) {
                $MFAUser['CAPolicies'] = try { $MFAUser['CAPolicies'] | ConvertFrom-Json -AsHashtable } catch { $MFAUser['CAPolicies'] }
            }
            if ($MFAUser['MFAMethods'] -is [string]) {
                $MFAUser['MFAMethods'] = try { $MFAUser['MFAMethods'] | ConvertFrom-Json -AsHashtable } catch { $MFAUser['MFAMethods'] }
            }

            $MFAUser['CacheTimestamp'] = $CacheTimestamp
            $AllMFAState.Add($MFAUser)
        }
        $MFAItems = $null

        if ($AllMFAState.Count -eq 0) {
            throw 'No MFA state data found in reporting database. Sync the report data first.'
        }

        # Sort by DisplayName with the keys extracted once.
        #
        # The [System.Collections.IComparer] cast is load bearing. Without it PowerShell
        # binds the items array to the generic Sort<TKey,TValue> overload, sorts a
        # converted throwaway copy, and returns with the keys reordered but the items
        # untouched - a silently unsorted response rather than an error. Casting the
        # comparer to the non-generic interface selects Sort(Array, Array, IComparer),
        # which reorders both arrays in place.
        $Sorted = $AllMFAState.ToArray()
        $AllMFAState = $null
        $SortKeys = [string[]]::new($Sorted.Length)
        for ($i = 0; $i -lt $Sorted.Length; $i++) { $SortKeys[$i] = [string]$Sorted[$i]['DisplayName'] }
        [Array]::Sort($SortKeys, $Sorted, [System.Collections.IComparer][StringComparer]::CurrentCultureIgnoreCase)

        return $Sorted

    } catch {
        Write-LogMessage -API 'MFAStateReport' -tenant $TenantFilter -message "Failed to generate MFA state report: $($_.Exception.Message)" -sev Error
        throw
    }
}
