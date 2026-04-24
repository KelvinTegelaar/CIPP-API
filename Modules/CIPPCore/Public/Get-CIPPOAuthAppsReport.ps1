function Get-CIPPOAuthAppsReport {
    <#
    .SYNOPSIS
        Generates an OAuth consented applications report from the CIPP Reporting database

    .DESCRIPTION
        Retrieves OAuth2 permission grants and enriches them with service principal data from the reporting database

    .PARAMETER TenantFilter
        The tenant to generate the report for
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    try {
        if ($TenantFilter -eq 'AllTenants') {
            $AllOAuthItems = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'OAuth2PermissionGrants'
            $Tenants = @($AllOAuthItems | Where-Object { $_.RowKey -ne 'OAuth2PermissionGrants-Count' } | Select-Object -ExpandProperty PartitionKey -Unique)

            $TenantList = Get-Tenants -IncludeErrors
            $Tenants = $Tenants | Where-Object { $TenantList.defaultDomainName -contains $_ }

            $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($Tenant in $Tenants) {
                try {
                    $TenantResults = Get-CIPPOAuthAppsReport -TenantFilter $Tenant
                    foreach ($Result in $TenantResults) {
                        $Result | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Tenant -Force
                        $AllResults.Add($Result)
                    }
                } catch {
                    Write-LogMessage -API 'OAuthAppsReport' -tenant $Tenant -message "Failed to get report for tenant: $($_.Exception.Message)" -sev Warning
                }
            }
            return $AllResults
        }

        $OAuthGrants = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'OAuth2PermissionGrants')
        if (-not $OAuthGrants) {
            throw 'No OAuth2 permission grant data found in reporting database. Sync the report data first.'
        }

        $ServicePrincipals = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ServicePrincipals')
        $SPLookup = @{}
        foreach ($SP in $ServicePrincipals) {
            if ($SP.id) {
                $SPLookup[$SP.id] = $SP
            }
        }

        $CacheTimestamp = (Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'OAuth2PermissionGrants' | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp

        $Results = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($Grant in $OAuthGrants) {
            $SP = $SPLookup[$Grant.clientId]
            $Results.Add([PSCustomObject]@{
                Name          = if ($SP) { $SP.displayName } else { $Grant.clientId }
                ApplicationID = if ($SP) { $SP.appId } else { '' }
                ObjectID      = $Grant.clientId
                Scope         = ($Grant.scope -join ',')
                StartTime     = $Grant.startTime
                CacheTimestamp = $CacheTimestamp
            })
        }

        return $Results | Sort-Object -Property Name

    } catch {
        Write-LogMessage -API 'OAuthAppsReport' -tenant $TenantFilter -message "Failed to generate OAuth apps report: $($_.Exception.Message)" -sev Error
        throw
    }
}
