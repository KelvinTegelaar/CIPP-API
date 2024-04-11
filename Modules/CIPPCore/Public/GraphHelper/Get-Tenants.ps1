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
        [switch]$IncludeErrors,
        [switch]$SkipDomains,
        [switch]$TriggerRefresh
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

    if (($IncludedTenantsCache | Measure-Object).Count -eq 0) {
        $BuildRequired = $true
    } 

    if ($BuildRequired -or $TriggerRefresh.IsPresent) {
        #get the full list of tenants
        $GDAPRelationships = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships?`$filter=status eq 'active' and not startsWith(displayName,'MLT_')&`$select=customer,autoExtendDuration,endDateTime" -NoAuthCheck:$true 
        $GDAPList = foreach ($Relationship in $GDAPRelationships) {
            [PSCustomObject]@{
                customerId      = $Relationship.customer.tenantId
                displayName     = $Relationship.customer.displayName
                autoExtend      = ($Relationship.autoExtendDuration -ne 'PT0S')
                relationshipEnd = $Relationship.endDateTime
            }
        }
        $ActiveRelationships = $GDAPList | Where-Object { $_.customerId -notin $SkipListCache.customerId }
        $TenantList = $ActiveRelationships | Group-Object -Property customerId | ForEach-Object -Parallel {
            Write-Host "Processing $($_.Name) to add to tenant list."
            Import-Module CIPPCore
            Import-Module AzBobbyTables
            $ExistingTenantInfo = Get-CIPPAzDataTableEntity @using:TenantsTable -Filter "PartitionKey eq 'Tenants' and RowKey eq '$($_.Name)'"
            if ($ExistingTenantInfo -and $ExistingInfo.RequiresRefresh -eq $false) {
                Write-Host 'Existing tenant found. We already have it cached, skipping.'
                $ExistingTenantInfo
                continue
            }
            $LatestRelationship = $_.Group | Sort-Object -Property relationshipEnd | Select-Object -Last 1
            $AutoExtend = ($_.Group | Where-Object { $_.autoExtend -eq $true } | Measure-Object).Count -gt 0

            if (-not $SkipDomains.IsPresent) {
                try {
                    Write-Host "Getting domains for $($_.Name)."
                    $Domains = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/domains' -tenantid $LatestRelationship.customerId -NoAuthCheck:$true -ErrorAction Stop
                    $defaultDomainName = ($Domains | Where-Object { $_.isDefault -eq $true }).id
                    $initialDomainName = ($Domains | Where-Object { $_.isInitial -eq $true }).id
                } catch {
                    try {
                        #doing alternative method to temporarily get domains. Nightly refresh will fix this as it will be marked for renew.
                        $Domain = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/tenantRelationships/findTenantInformationByTenantId(tenantId='$($LatestRelationship.customerId)')" -NoAuthCheck:$true).defaultDomainName
                        $defaultDomainName = $Domain
                        $initialDomainName = $Domain
                        $RequiresRefresh = $true
                        
                    } catch {
                        Write-LogMessage -API 'Get-Tenants' -message "Tried adding $($LatestRelationship.customerId) to tenant list but failed to get domains - $($_.Exception.Message)" -level 'Critical'

                    }
                }
       
                [PSCustomObject]@{
                    PartitionKey             = 'Tenants'
                    RowKey                   = $_.Name
                    customerId               = $_.Name
                    displayName              = $LatestRelationship.displayName
                    relationshipEnd          = $LatestRelationship.relationshipEnd
                    relationshipCount        = $_.Count
                    defaultDomainName        = $defaultDomainName
                    initialDomainName        = $initialDomainName
                    hasAutoExtend            = $AutoExtend
                    delegatedPrivilegeStatus = 'granularDelegatedAdminPrivileges'
                    domains                  = ''
                    Excluded                 = $false
                    ExcludeUser              = ''
                    ExcludeDate              = ''
                    GraphErrorCount          = 0
                    LastGraphError           = ''
                    RequiresRefresh          = [bool]$RequiresRefresh
                    LastRefresh              = (Get-Date).ToUniversalTime()
                }
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
    }

    if ($IncludedTenantsCache) {
        Add-CIPPAzDataTableEntity @TenantsTable -Entity $IncludedTenantsCache -Force
        $CurrentTenants = Get-CIPPAzDataTableEntity @TenantsTable -Filter "PartitionKey eq 'Tenants' and Excluded eq false"
        $CurrentTenants | Where-Object { $_.customerId -notin $IncludedTenantsCache.customerId } | ForEach-Object {
            Remove-AzDataTableEntity -Context $TenantsTable -Entity $_ -Force
        }
    }
    return ($IncludedTenantsCache | Where-Object { $null -ne $_.defaultDomainName -and ($_.defaultDomainName -notmatch 'Domain Error' -or $IncludeAll.IsPresent) } | Sort-Object -Property displayName)
}
