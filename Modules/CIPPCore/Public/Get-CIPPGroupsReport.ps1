function Get-CIPPGroupsReport {
    <#
    .SYNOPSIS
        Generates a groups report from the CIPP Reporting database

    .PARAMETER TenantFilter
        The tenant to generate the report for, or 'AllTenants' for all tenants

    .PARAMETER PageSize
        When set, returns one page of at most this many rows as @{ Items; NextToken }, in table walk order.

    .PARAMETER ContinuationToken
        NextToken from the previous page. Only meaningful together with PageSize.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [int]$PageSize,
        [string]$ContinuationToken,
        # Return one page as { CippPagedJson; NextToken }: the stored blobs stitched into a
        # JSON array verbatim, with per-row CacheTimestamp/Tenant spliced in. No member array
        # is ever deserialized on the read path.
        [switch]$AsRawJson
    )

    if ($PageSize -gt 0) {
        $Page = Get-CIPPDbItemPage -TenantFilter $TenantFilter -Type 'Groups' -PageSize $PageSize -ContinuationToken $ContinuationToken
        if ($TenantFilter -ne 'AllTenants' -and -not $ContinuationToken -and @($Page.Items).Count -eq 0 -and -not $Page.NextToken) {
            throw "No groups data found in reporting database for $TenantFilter. Sync the report data first."
        }

        if ($AsRawJson) {
            $IsAllTenants = $TenantFilter -eq 'AllTenants'
            $Builder = [System.Text.StringBuilder]::new()
            $null = $Builder.Append('[')
            $First = $true
            foreach ($Item in $Page.Items) {
                $Blob = [string]$Item.Data
                if ([string]::IsNullOrWhiteSpace($Blob)) { continue }
                $Blob = $Blob.Trim()
                if ($Blob[0] -ne '{') { continue }
                if (-not $First) { $null = $Builder.Append(',') }
                $First = $false
                # Emit the blob verbatim, then splice the two row-level fields onto its closing
                # brace. membersCsv/ownersCsv already live in the blob (written at cache time).
                $null = $Builder.Append($Blob, 0, $Blob.Length - 1)
                $null = $Builder.Append(',"CacheTimestamp":').Append((ConvertTo-Json -InputObject $Item.Timestamp -Compress))
                if ($IsAllTenants) {
                    $null = $Builder.Append(',"Tenant":').Append((ConvertTo-Json -InputObject ([string]$Item.PartitionKey) -Compress))
                }
                $null = $Builder.Append('}')
            }
            $null = $Builder.Append(']')
            return [PSCustomObject]@{
                CippPagedJson = $Builder.ToString()
                NextToken     = $Page.NextToken
            }
        }

        $Results = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Item in $Page.Items) {
            try {
                $Group = $Item.Data | ConvertFrom-Json -Depth 10 -ErrorAction Stop
                # Collect every note property once, then attach in a single Add-Member call.
                $NewProps = [ordered]@{}
                if ($Group.members -and -not $Group.membersCsv) {
                    $NewProps['membersCsv'] = $Group.members.userPrincipalName -join ','
                }
                if ($Group.owners -and -not $Group.ownersCsv) {
                    $NewProps['ownersCsv'] = $Group.owners.userPrincipalName -join ','
                }
                if ($null -eq $Group.hasOwner) {
                    # Use the freshly computed ownersCsv if we just built one, else the stored value.
                    $OwnersCsv = if ($NewProps.Contains('ownersCsv')) { $NewProps['ownersCsv'] } else { $Group.ownersCsv }
                    $NewProps['hasOwner'] = -not [string]::IsNullOrEmpty($OwnersCsv)
                }
                # Per-item timestamp: a page may span tenants.
                $NewProps['CacheTimestamp'] = $Item.Timestamp
                if ($TenantFilter -eq 'AllTenants') {
                    $NewProps['Tenant'] = $Item.PartitionKey
                }
                $Group | Add-Member -NotePropertyMembers $NewProps -Force
                $Results.Add($Group)
            } catch {
                Write-LogMessage -API 'GroupsReport' -tenant $Item.PartitionKey -message "Failed to parse group item: $($_.Exception.Message)" -sev Warning
            }
        }
        return [PSCustomObject]@{
            Items     = $Results
            NextToken = $Page.NextToken
        }
    }

    if ($TenantFilter -eq 'AllTenants') {
        $AnyItems = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'Groups'
        $Tenants = @($AnyItems | Where-Object { $_.RowKey -notlike '*-Count' } | Select-Object -ExpandProperty PartitionKey -Unique)
        $TenantList = Get-Tenants -IncludeErrors
        $Tenants = $Tenants | Where-Object { $TenantList.defaultDomainName -contains $_ }

        $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Tenant in $Tenants) {
            try {
                $TenantResults = Get-CIPPGroupsReport -TenantFilter $Tenant
                foreach ($Result in $TenantResults) {
                    $Result | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Tenant -Force
                    $AllResults.Add($Result)
                }
            } catch {
                Write-LogMessage -API 'GroupsReport' -tenant $Tenant -message "Failed to get groups report: $($_.Exception.Message)" -sev Warning
            }
        }
        return $AllResults
    }

    $Items = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'Groups' | Where-Object { $_.RowKey -notlike '*-Count' }
    if (-not $Items) {
        throw "No groups data found in reporting database for $TenantFilter. Sync the report data first."
    }

    $CacheTimestamp = ($Items | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp

    $Results = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($Item in $Items) {
        try {
            $Group = $Item.Data | ConvertFrom-Json -Depth 10 -ErrorAction Stop
            # Collect every note property once, then attach in a single Add-Member call.
            $NewProps = [ordered]@{}
            if ($Group.members -and -not $Group.membersCsv) {
                $NewProps['membersCsv'] = $Group.members.userPrincipalName -join ','
            }
            if ($Group.owners -and -not $Group.ownersCsv) {
                $NewProps['ownersCsv'] = $Group.owners.userPrincipalName -join ','
            }
            # Use the freshly computed ownersCsv if we just built one, else the stored value.
            $OwnersCsv = if ($NewProps.Contains('ownersCsv')) { $NewProps['ownersCsv'] } else { $Group.ownersCsv }
            $NewProps['hasOwner'] = -not [string]::IsNullOrEmpty($OwnersCsv)
            $NewProps['CacheTimestamp'] = $CacheTimestamp
            $Group | Add-Member -NotePropertyMembers $NewProps -Force
            $Results.Add($Group)
        } catch {
            Write-LogMessage -API 'GroupsReport' -tenant $TenantFilter -message "Failed to parse group item: $($_.Exception.Message)" -sev Warning
        }
    }

    return ($Results | Sort-Object displayName)
}
