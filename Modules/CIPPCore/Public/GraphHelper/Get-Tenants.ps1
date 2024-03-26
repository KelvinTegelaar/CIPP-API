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

        # Query for active relationships
        $GDAPRelationships = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships?`$filter=status eq 'active'&`$select=customer,autoExtendDuration,endDateTime"

        # Flatten gdap relationship
        $GDAPList = foreach ($Relationship in $GDAPRelationships) {
            [PSCustomObject]@{
                customerId      = $Relationship.customer.tenantId
                displayName     = $Relationship.customer.displayName
                autoExtend      = ($Relationship.autoExtendDuration -ne 'PT0S')
                relationshipEnd = $Relationship.endDateTime
            }
        }

        # Group relationships, build object for adding to tables
        $ActiveRelationships = $GDAPList | Where-Object { $_.customerId -notin $SkipListCache.customerId }
        $TenantList = $ActiveRelationships | Group-Object -Property customerId | ForEach-Object -Parallel {
            Import-Module .\Modules\CIPPCore
            $LatestRelationship = $_.Group | Sort-Object -Property relationshipEnd | Select-Object -Last 1
            $AutoExtend = ($_.Group | Where-Object { $_.autoExtend -eq $true } | Measure-Object).Count -gt 0

            # Query domains to get default/initial
            $Domains = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/domains' -tenantid $LatestRelationship.customerId -NoAuthCheck:$true
            [PSCustomObject]@{
                PartitionKey             = 'Tenants'
                RowKey                   = $_.Name
                customerId               = $_.Name
                displayName              = $LatestRelationship.displayName
                relationshipEnd          = $LatestRelationship.relationshipEnd
                relationshipCount        = $_.Count
                defaultDomainName        = ($Domains | Where-Object { $_.isDefault -eq $true }).id
                initialDomainName        = ($Domains | Where-Object { $_.isInitial -eq $true }).id
                hasAutoExtend            = $AutoExtend
                delegatedPrivilegeStatus = 'granularDelegatedAdminPrivileges'
                domains                  = ''
                Excluded                 = $false
                ExcludeUser              = ''
                ExcludeDate              = ''
                GraphErrorCount          = 0
                LastGraphError           = ''
                LastRefresh              = (Get-Date).ToUniversalTime()
            }
        }

        $IncludedTenantsCache = [system.collections.generic.list[object]]::new()
        if ($env:PartnerTenantAvailable) {
            # Add partner tenant if env is set
            $IncludedTenantsCache.Add([PSCustomObject]@{
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
            $IncludedTenantsCache.Add($Tenant) | Out-Null
        }

        if ($IncludedTenantsCache) {
            $TenantsTable.Force = $true
            Add-CIPPAzDataTableEntity @TenantsTable -Entity $IncludedTenantsCache
        }
    }
    return ($IncludedTenantsCache | Where-Object -Property defaultDomainName -NE $null | Sort-Object -Property displayName)

}
