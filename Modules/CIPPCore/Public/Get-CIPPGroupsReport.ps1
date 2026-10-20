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
        # Return one page as { CippPagedJson; NextToken }: the stored blobs rewritten into a
        # JSON array without their members array, with per-row CacheTimestamp/Tenant added.
        # No blob is ever deserialized into PowerShell objects on the read path.
        [switch]$AsRawJson,

        # Rows already read by the AllTenants path, keyed by cache type
        [Parameter(DontShow = $true)]
        [hashtable]$DbItems
    )

    if ($PageSize -gt 0) {
        $Page = Get-CIPPDbItemPage -TenantFilter $TenantFilter -Type 'Groups' -PageSize $PageSize -ContinuationToken $ContinuationToken
        if ($TenantFilter -ne 'AllTenants' -and -not $ContinuationToken -and @($Page.Items).Count -eq 0 -and -not $Page.NextToken) {
            throw "No groups data found in reporting database for $TenantFilter. Sync the report data first."
        }

        if ($AsRawJson) {
            $IsAllTenants = $TenantFilter -eq 'AllTenants'
            $Stream = [System.IO.MemoryStream]::new()
            $Writer = [System.Text.Json.Utf8JsonWriter]::new($Stream)
            $Writer.WriteStartArray()
            foreach ($Item in $Page.Items) {
                $Blob = [string]$Item.Data
                if ([string]::IsNullOrWhiteSpace($Blob)) { continue }
                try { $Doc = [System.Text.Json.JsonDocument]::Parse($Blob) } catch { continue }
                try {
                    if ($Doc.RootElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) { continue }
                    # The list shows membersCsv; the full members array is several times the rest of the row.
                    $Writer.WriteStartObject()
                    foreach ($Property in $Doc.RootElement.EnumerateObject()) {
                        if ($Property.Name -ne 'members') { $Property.WriteTo($Writer) }
                    }
                    $Writer.WritePropertyName('CacheTimestamp')
                    $Writer.WriteRawValue((ConvertTo-Json -InputObject $Item.Timestamp -Compress))
                    if ($IsAllTenants) { $Writer.WriteString('Tenant', [string]$Item.PartitionKey) }
                    $Writer.WriteEndObject()
                } finally {
                    $Doc.Dispose()
                }
            }
            $Writer.WriteEndArray()
            $Writer.Flush()
            $Writer.Dispose()
            return [PSCustomObject]@{
                CippPagedJson = [System.Text.Encoding]::UTF8.GetString($Stream.GetBuffer(), 0, [int]$Stream.Length)
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
        $ItemsByTenant = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'Groups' -ByTenant

        $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Tenant in @($ItemsByTenant.Keys)) {
            # Hand each tenant its rows and drop them here so they can be freed once processed
            $TenantItems = $ItemsByTenant[$Tenant]; $ItemsByTenant[$Tenant] = $null
            try {
                $TenantResults = Get-CIPPGroupsReport -TenantFilter $Tenant -DbItems @{ Groups = $TenantItems }
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

    $Items = $(if ($DbItems) { $DbItems['Groups'] } else { Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'Groups' }) | Where-Object { $_.RowKey -notlike '*-Count' }
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
