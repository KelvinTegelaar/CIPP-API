function Get-CIPPGroupsReport {
    <#
    .SYNOPSIS
        Generates a groups report from the CIPP Reporting database

    .PARAMETER TenantFilter
        The tenant to generate the report for, or 'AllTenants' for all tenants
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

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
            if ($Group.members -and -not $Group.membersCsv) {
                $Group | Add-Member -NotePropertyName 'membersCsv' -NotePropertyValue ($Group.members.userPrincipalName -join ',') -Force
            }
            $Group | Add-Member -NotePropertyName 'CacheTimestamp' -NotePropertyValue $CacheTimestamp -Force
            $Results.Add($Group)
        } catch {
            Write-LogMessage -API 'GroupsReport' -tenant $TenantFilter -message "Failed to parse group item: $($_.Exception.Message)" -sev Warning
        }
    }

    return ($Results | Sort-Object displayName)
}
