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
        [switch]$TriggerRefresh,
        [switch]$CleanOld
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

    if ($CleanOld) {
        $GDAPRelationships = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships?`$filter=status eq 'active' and not startsWith(displayName,'MLT_')&`$select=customer,autoExtendDuration,endDateTime`$top=300" -NoAuthCheck:$true
        $GDAPList = foreach ($Relationship in $GDAPRelationships) {
            [PSCustomObject]@{
                customerId      = $Relationship.customer.tenantId
                displayName     = $Relationship.customer.displayName
                autoExtend      = ($Relationship.autoExtendDuration -ne 'PT0S')
                relationshipEnd = $Relationship.endDateTime
            }
        }
        $CurrentTenants = Get-CIPPAzDataTableEntity @TenantsTable -Filter "PartitionKey eq 'Tenants' and Excluded eq false"
        $CurrentTenants | Where-Object { $_.customerId -notin $GDAPList.customerId } | ForEach-Object {
            Remove-AzDataTableEntity @TenantsTable -Entity $_
        }
    }
    $PartnerModeTable = Get-CippTable -tablename 'tenantMode'
    $PartnerTenantState = Get-CIPPAzDataTableEntity @PartnerModeTable

    if (($BuildRequired -or $TriggerRefresh.IsPresent) -and $PartnerTenantState.state -ne 'owntenant') {
        #get the full list of tenants
        $GDAPRelationships = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships?`$filter=status eq 'active' and not startsWith(displayName,'MLT_')&`$select=customer,autoExtendDuration,endDateTime&`$top=300" -NoAuthCheck:$true
        $GDAPList = foreach ($Relationship in $GDAPRelationships) {
            [PSCustomObject]@{
                customerId      = $Relationship.customer.tenantId
                displayName     = $Relationship.customer.displayName
                autoExtend      = ($Relationship.autoExtendDuration -ne 'PT0S')
                relationshipEnd = $Relationship.endDateTime
            }
        }

        $ActiveRelationships = $GDAPList | Where-Object { $_.customerId -notin $SkipListCache.customerId }
        $TenantList = $ActiveRelationships | Group-Object -Property customerId | ForEach-Object {
            Write-Host "Processing $($_.Name) to add to tenant list."
            $ExistingTenantInfo = Get-CIPPAzDataTableEntity @TenantsTable -Filter "PartitionKey eq 'Tenants' and RowKey eq '$($_.Name)'"

            if ($TriggerRefresh.IsPresent -and $ExistingTenantInfo.customerId) {
                # Reset error count
                $ExistingTenantInfo.GraphErrorCount = 0
                Add-CIPPAzDataTableEntity @TenantsTable -Entity $ExistingTenantInfo -Force | Out-Null
            }

            if ($ExistingTenantInfo -and $ExistingTenantInfo.RequiresRefresh -eq $false) {
                Write-Host 'Existing tenant found. We already have it cached, skipping.'
                $ExistingTenantInfo
                return
            }
            $LatestRelationship = $_.Group | Sort-Object -Property relationshipEnd | Select-Object -Last 1
            $AutoExtend = ($_.Group | Where-Object { $_.autoExtend -eq $true } | Measure-Object).Count -gt 0

            if (-not $SkipDomains.IsPresent) {
                try {
                    Write-Host "Getting domains for $($_.Name)."
                    $Domains = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/domains?$top=999' -tenantid $LatestRelationship.customerId -NoAuthCheck:$true -ErrorAction Stop
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
        if ($PartnerTenantState.state -eq 'PartnerTenantAvailable') {
            # Add partner tenant if env is set
            $Domains = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/domains?$top=999' -tenantid $env:TenantID -NoAuthCheck:$true
            $IncludedTenantsCache.Add([PSCustomObject]@{
                    RowKey            = $env:TenantID
                    PartitionKey      = 'Tenants'
                    customerId        = $env:TenantID
                    defaultDomainName = ($Domains | Where-Object { $_.isInitial -eq $true }).id
                    initialDomainName = ($Domains | Where-Object { $_.isInitial -eq $true }).id
                    displayName       = '*Partner Tenant'
                    domains           = 'PartnerTenant'
                    Excluded          = $false
                    ExcludeUser       = ''
                    ExcludeDate       = ''
                    GraphErrorCount   = 0
                    LastGraphError    = ''
                    RequiresRefresh   = [bool]$RequiresRefresh
                    LastRefresh       = (Get-Date).ToUniversalTime()
                }) | Out-Null
        }
        foreach ($Tenant in $TenantList) {
            if ($Tenant.defaultDomainName -eq 'Invalid' -or !$Tenant.defaultDomainName) {
                Write-LogMessage -API 'Get-Tenants' -message "We're skipping $($Tenant.displayName) as it has an invalid default domain name. Something is up with this instance." -level 'Critical'
                continue
            }
            $IncludedTenantsCache.Add($Tenant) | Out-Null
        }

        if ($IncludedTenantsCache) {
            Add-CIPPAzDataTableEntity @TenantsTable -Entity $IncludedTenantsCache -Force | Out-Null
        }
    }
    if ($PartnerTenantState.state -eq 'owntenant' -and $IncludedTenantsCache.RowKey.count -eq 0) {
        $Domains = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/domains' -tenantid $env:TenantID -NoAuthCheck:$true

        $IncludedTenantsCache = @([PSCustomObject]@{
                RowKey            = $env:TenantID
                PartitionKey      = 'Tenants'
                customerId        = $env:TenantID
                defaultDomainName = ($Domains | Where-Object { $_.isInitial -eq $true }).id
                initialDomainName = ($Domains | Where-Object { $_.isInitial -eq $true }).id
                displayName       = ($Domains | Where-Object { $_.isInitial -eq $true }).id
                domains           = 'PartnerTenant'
                Excluded          = $false
                ExcludeUser       = ''
                ExcludeDate       = ''
                GraphErrorCount   = 0
                LastGraphError    = ''
                RequiresRefresh   = [bool]$RequiresRefresh
                LastRefresh       = (Get-Date).ToUniversalTime()
            })
        if ($IncludedTenantsCache) {
            Add-CIPPAzDataTableEntity @TenantsTable -Entity $IncludedTenantsCache -Force | Out-Null
        }
    }

    return ($IncludedTenantsCache | Where-Object { $null -ne $_.defaultDomainName -and ($_.defaultDomainName -notmatch 'Domain Error' -or $IncludeAll.IsPresent) } | Sort-Object -Property displayName)
}
