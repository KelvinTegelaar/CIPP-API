function Invoke-ListSiteActivity {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    .DESCRIPTION
        Lists cached site activity rows from the CIPP reporting database for SharePoint and Teams sites.
        Supports tenantFilter and optional Type filter (SharePoint or TeamsSite).
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = 'ListSiteActivity'
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $Type = $Request.Query.Type ?? $Request.Body.Type

    if (-not $TenantFilter) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = 'tenantFilter is required'
            })
    }

    if ($Type -and $Type -notin @('SharePoint', 'TeamsSite')) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = 'Type must be SharePoint or TeamsSite'
            })
    }

    try {
        $TypeMap = @{
            SharePoint = 'SharePoint'
            TeamsSite  = 'SharePointAndTeams'
        }
        $SelectedSiteType = if ($Type) { $TypeMap[$Type] } else { $null }

        $AllResults = [System.Collections.Generic.List[object]]::new()

        if ($TenantFilter -eq 'AllTenants') {
            $AnyItems = Get-CIPPDbItem -TenantFilter 'allTenants' -Type 'SiteActivity'
            $Tenants = @($AnyItems | Where-Object { $_.RowKey -notlike '*-Count' } | Select-Object -ExpandProperty PartitionKey -Unique)

            $TenantList = Get-Tenants -IncludeErrors
            $Tenants = $Tenants | Where-Object { $TenantList.defaultDomainName -contains $_ }

            foreach ($Tenant in $Tenants) {
                try {
                    $TenantRows = @(New-CIPPDbRequest -TenantFilter $Tenant -Type 'SiteActivity')
                    if (-not $TenantRows) { continue }

                    $CountRow = Get-CIPPDbItem -TenantFilter $Tenant -Type 'SiteActivity' -CountsOnly | Select-Object -First 1
                    $CacheTimestamp = $CountRow.Timestamp

                    foreach ($Row in $TenantRows) {
                        if ($Row.siteType -eq 'OneDrive') { continue }
                        if ($SelectedSiteType -and $Row.siteType -ne $SelectedSiteType) { continue }

                        $Row | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $Tenant -Force
                        $Row | Add-Member -NotePropertyName 'CacheTimestamp' -NotePropertyValue $CacheTimestamp -Force
                        [void]$AllResults.Add($Row)
                    }
                } catch {
                    Write-LogMessage -API $APIName -tenant $Tenant -message "Failed to retrieve cached site activity: $($_.Exception.Message)" -sev Warning
                }
            }
        } else {
            $TenantRows = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'SiteActivity')
            $CountRow = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'SiteActivity' -CountsOnly | Select-Object -First 1
            $CacheTimestamp = $CountRow.Timestamp

            foreach ($Row in $TenantRows) {
                if ($Row.siteType -eq 'OneDrive') { continue }
                if ($SelectedSiteType -and $Row.siteType -ne $SelectedSiteType) { continue }

                $Row | Add-Member -NotePropertyName 'CacheTimestamp' -NotePropertyValue $CacheTimestamp -Force
                [void]$AllResults.Add($Row)
            }
        }

        $GraphRequest = @($AllResults | Sort-Object -Property displayName)
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Failed to list site activity: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
        $GraphRequest = @{ Error = $ErrorMessage.NormalizedError }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })
}
