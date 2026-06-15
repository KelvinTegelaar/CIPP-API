function Invoke-ExecUniversalSearchV2 {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $SearchTerms = $Request.Query.searchTerms
    $Limit = if ($Request.Query.limit) { [int]$Request.Query.limit } else { 10 }
    $Type = if ($Request.Query.type) { $Request.Query.type } else { 'Users' }

    $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList

    if ($AllowedTenants -notcontains 'AllTenants') {
        $TenantFilter = Get-Tenants | Select-Object -ExpandProperty defaultDomainName
    } else {
        $TenantFilter = 'allTenants'
    }

    # Always search all tenants - do not pass TenantFilter parameter
    switch ($Type) {
        'Users' {
            $Results = Search-CIPPDbData -SearchTerms $SearchTerms -Types 'Users' -Limit $Limit -Properties 'id', 'userPrincipalName', 'displayName' -TenantFilter $TenantFilter
        }
        'Groups' {
            $Results = Search-CIPPDbData -SearchTerms $SearchTerms -Types 'Groups' -Limit $Limit -Properties 'id', 'displayName', 'mail', 'mailEnabled', 'securityEnabled', 'groupTypes', 'description' -TenantFilter $TenantFilter
        }
        'Applications' {
            $Results = Search-CIPPDbData -SearchTerms $SearchTerms -Types 'Apps', 'ServicePrincipals' -Limit $Limit -Properties 'id', 'appId', 'displayName', 'publisherName', 'appOwnerOrganizationId' -TenantFilter $TenantFilter
        }
        'Licenses' {
            # SKU lookup is universal — always search across all tenants regardless of caller scope.
            # No Properties filter so service plan names / friendly names embedded in the JSON
            # still pass the secondary verification pass.
            $Raw = Search-CIPPDbData -SearchTerms $SearchTerms -Types 'LicenseOverview' -TenantFilter 'allTenants'

            $BySku = [ordered]@{}
            foreach ($Row in $Raw) {
                $Data = $Row.Data
                if (-not $Data -or [string]::IsNullOrWhiteSpace($Data.skuId)) { continue }
                $Key = ([string]$Data.skuId).ToLowerInvariant()

                if (-not $BySku.Contains($Key)) {
                    $BySku[$Key] = [PSCustomObject]@{
                        skuId          = [string]$Data.skuId
                        skuPartNumber  = [string]$Data.skuPartNumber
                        displayName    = [string]$Data.License
                        servicePlans   = @($Data.ServicePlans)
                        tenantCount    = 0
                        totalAssigned  = 0
                        totalAvailable = 0
                        tenants        = [System.Collections.Generic.List[object]]::new()
                    }
                }

                $Entry = $BySku[$Key]
                if ([string]::IsNullOrWhiteSpace($Entry.skuPartNumber) -and $Data.skuPartNumber) { $Entry.skuPartNumber = [string]$Data.skuPartNumber }
                if ([string]::IsNullOrWhiteSpace($Entry.displayName) -and $Data.License) { $Entry.displayName = [string]$Data.License }
                if ((-not $Entry.servicePlans -or $Entry.servicePlans.Count -eq 0) -and $Data.ServicePlans) { $Entry.servicePlans = @($Data.ServicePlans) }

                $Entry.tenantCount++
                $Used = 0; [int]::TryParse([string]$Data.CountUsed, [ref]$Used) | Out-Null
                $Total = 0; [int]::TryParse([string]$Data.TotalLicenses, [ref]$Total) | Out-Null
                $Entry.totalAssigned += $Used
                $Entry.totalAvailable += $Total
                $Entry.tenants.Add([PSCustomObject]@{
                        tenant = [string]$Row.Tenant
                        used   = $Used
                        total  = $Total
                    })
            }

            $Aggregated = $BySku.Values | Sort-Object -Property tenantCount -Descending | Select-Object -First $Limit

            # Shape into the same envelope as other types so the frontend can use match.Data
            $Results = foreach ($Item in $Aggregated) {
                [PSCustomObject]@{
                    Tenant = ''
                    Type   = 'Licenses'
                    RowKey = "Licenses-$($Item.skuId)"
                    Data   = $Item
                }
            }
        }
        default {
            $Results = Search-CIPPDbData -SearchTerms $SearchTerms -Types 'Users' -Limit $Limit -Properties 'id', 'userPrincipalName', 'displayName' -TenantFilter $TenantFilter
        }
    }

    Write-Information "Results: $($Results | ConvertTo-Json -Depth 10)"

    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($Results)
    }

}
