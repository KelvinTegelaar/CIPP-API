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
        [string]$TenantFilter,

        # Rows already read by the AllTenants path, keyed by cache type
        [Parameter(DontShow = $true)]
        [hashtable]$DbItems
    )

    try {
        if ($TenantFilter -eq 'AllTenants') {
            $ItemsByTenant = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'OAuth2PermissionGrants' -ByTenant

            $AllResults = [System.Collections.Generic.List[PSCustomObject]]::new()
            foreach ($Tenant in @($ItemsByTenant.Keys)) {
                # Hand each tenant its rows and drop them here so they can be freed once processed
                $TenantItems = $ItemsByTenant[$Tenant]; $ItemsByTenant[$Tenant] = $null
                try {
                    $TenantResults = Get-CIPPOAuthAppsReport -TenantFilter $Tenant -DbItems @{ OAuth2PermissionGrants = $TenantItems }
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

        # The count row is kept: its timestamp is the cache time reported below
        $GrantItems = $(if ($DbItems) { $DbItems['OAuth2PermissionGrants']; Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'OAuth2PermissionGrants' -CountsOnly } else { Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'OAuth2PermissionGrants' })
        $OAuthGrants = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'OAuth2PermissionGrants' -Rows $GrantItems)
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

        $CacheTimestamp = ($GrantItems | Where-Object { $_.Timestamp } | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp

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
