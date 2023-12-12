function Get-Tenants {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param (
        [Parameter( ParameterSetName = 'Skip', Mandatory = $True )]
        [switch]$SkipList,
        [Parameter( ParameterSetName = 'Standard')]
        [switch]$IncludeAll,
        [switch]$IncludeErrors
    )

    $TenantsTable = Get-CippTable -tablename 'Tenants'
    $ExcludedFilter = "PartitionKey eq 'Tenants' and Excluded eq true"

    $SkipListCache = Get-CIPPAzDataTableEntity @TenantsTable -Filter $ExcludedFilter
    if ($SkipList) {
        return $SkipListCache
    }

    if ($IncludeAll.IsPresent) {
        $Filter = "PartitionKey eq 'Tenants'"
    } elseif ($IncludeErrors.IsPresent) {
        $Filter = "PartitionKey eq 'Tenants' and Excluded eq false"
    } else {
        $Filter = "PartitionKey eq 'Tenants' and Excluded eq false and GraphErrorCount lt 50"
    }
    $IncludedTenantsCache = Get-CIPPAzDataTableEntity @TenantsTable -Filter $Filter

    if (($IncludedTenantsCache | Measure-Object).Count -gt 0) {
        try {
            $LastRefresh = ($IncludedTenantsCache | Where-Object { $_.customerId } | Sort-Object LastRefresh -Descending | Select-Object -First 1).LastRefresh | Get-Date -ErrorAction Stop
        } catch { $LastRefresh = $false }
    } else {
        $LastRefresh = $false
    }
    if (!$LastRefresh -or $LastRefresh -lt (Get-Date).Addhours(-24).ToUniversalTime()) {
        try {
            Write-Host "Renewing. Cache not hit. $LastRefresh"
            $TenantList = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/managedTenants/tenants?`$top=999" -tenantid $env:TenantID ) | Select-Object id, @{l = 'customerId'; e = { $_.tenantId } }, @{l = 'DefaultdomainName'; e = { [string]($_.contract.defaultDomainName) } } , @{l = 'MigratedToNewTenantAPI'; e = { $true } }, DisplayName, domains, @{n = 'delegatedPrivilegeStatus'; exp = { $_.tenantStatusInformation.delegatedPrivilegeStatus } } | Where-Object { $_.defaultDomainName -NotIn $SkipListCache.defaultDomainName -and $_.defaultDomainName -ne $null }

        } catch {
            Write-Host "Get-Tenants - Lighthouse Error, using contract/delegatedAdminRelationship calls. Error: $($_.Exception.Message)"
            [System.Collections.Generic.List[PSCustomObject]]$BulkRequests = @(
                @{
                    id     = 'Contracts'
                    method = 'GET'
                    url    = "/contracts?`$top=999"
                },
                @{
                    id     = 'GDAPRelationships'
                    method = 'GET'
                    url    = '/tenantRelationships/delegatedAdminRelationships'
                }
            )

            $BulkResults = New-GraphBulkRequest -Requests $BulkRequests -tenantid $TenantFilter -NoAuthCheck:$true
            $Contracts = Get-GraphBulkResultByID -Results $BulkResults -ID 'Contracts' -Value
            $GDAPRelationships = Get-GraphBulkResultByID -Results $BulkResults -ID 'GDAPRelationships' -Value

            $ContractList = $Contracts | Select-Object id, customerId, DefaultdomainName, DisplayName, domains, @{l = 'MigratedToNewTenantAPI'; e = { $true } }, @{ n = 'delegatedPrivilegeStatus'; exp = { $CustomerId = $_.customerId; if (($GDAPRelationships | Where-Object { $_.customer.tenantId -EQ $CustomerId -and $_.status -EQ 'active' } | Measure-Object).Count -gt 0) { 'delegatedAndGranularDelegetedAdminPrivileges' } else { 'delegatedAdminPrivileges' } } } | Where-Object -Property defaultDomainName -NotIn $SkipListCache.defaultDomainName

            $GDAPOnlyList = $GDAPRelationships | Where-Object { $_.status -eq 'active' -and $Contracts.customerId -notcontains $_.customer.tenantId } | Select-Object id, @{l = 'customerId'; e = { $($_.customer.tenantId) } }, @{l = 'defaultDomainName'; e = { (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/findTenantInformationByTenantId(tenantId='$($_.customer.tenantId)')" -noauthcheck $true -asApp:$true -tenant $env:TenantId).defaultDomainName } }, @{l = 'MigratedToNewTenantAPI'; e = { $true } }, @{n = 'displayName'; exp = { $_.customer.displayName } }, domains, @{n = 'delegatedPrivilegeStatus'; exp = { 'granularDelegatedAdminPrivileges' } } | Where-Object { $_.defaultDomainName -NotIn $SkipListCache.defaultDomainName -and $_.defaultDomainName -ne $null } | Sort-Object -Property customerId -Unique

            $TenantList = @($ContractList) + @($GDAPOnlyList)
        }
        <#if (!$TenantList.customerId) {
            $TenantList = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/contracts?`$top=999" -tenantid $env:TenantID ) | Select-Object id, customerId, DefaultdomainName, DisplayName, domains | Where-Object -Property defaultDomainName -NotIn $SkipListCache.defaultDomainName
        }#>
        $IncludedTenantsCache = [system.collections.generic.list[hashtable]]::new()
        if ($env:PartnerTenantAvailable) {
            $IncludedTenantsCache.Add(@{
                    RowKey            = $env:TenantID
                    PartitionKey      = 'Tenants'
                    customerId        = $env:TenantID
                    defaultDomainName = $env:TenantID
                    displayName       = '*Partner Tenant'
                    domains           = 'PartnerTenant'
                    Excluded          = $false
                    ExcludeUser       = ''
                    ExcludeDate       = ''
                    GraphErrorCount   = 0
                    LastGraphError    = ''
                    LastRefresh       = (Get-Date).ToUniversalTime()
                }) | Out-Null
        }
        foreach ($Tenant in $TenantList) {
            if ($Tenant.defaultDomainName -eq 'Invalid' -or !$Tenant.defaultDomainName) { continue }
            $IncludedTenantsCache.Add(@{
                    RowKey                   = [string]$Tenant.customerId
                    PartitionKey             = 'Tenants'
                    customerId               = [string]$Tenant.customerId
                    defaultDomainName        = [string]$Tenant.defaultDomainName
                    displayName              = [string]$Tenant.DisplayName
                    delegatedPrivilegeStatus = [string]$Tenant.delegatedPrivilegeStatus
                    domains                  = ''
                    Excluded                 = $false
                    ExcludeUser              = ''
                    ExcludeDate              = ''
                    GraphErrorCount          = 0
                    LastGraphError           = ''
                    LastRefresh              = (Get-Date).ToUniversalTime()
                }) | Out-Null
        }

        if ($IncludedTenantsCache) {
            $TenantsTable.Force = $true
            Add-CIPPAzDataTableEntity @TenantsTable -Entity $IncludedTenantsCache
        }
    }
    return ($IncludedTenantsCache | Where-Object -Property defaultDomainName -NE $null | Sort-Object -Property displayName)

}
