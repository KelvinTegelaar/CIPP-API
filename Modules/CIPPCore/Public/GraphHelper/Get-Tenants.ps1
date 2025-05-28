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
        [switch]$CleanOld,
        [string]$TenantFilter
    )
    #$caller = $MyInvocation.InvocationName
    #$scriptName = $MyInvocation.ScriptName
    #Write-Host "Called by: $caller"
    #Write-Host "In script: $scriptName"
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

    if ($TenantFilter) {
        #Write-Information "Getting tenant $TenantFilter"
        if ($TenantFilter -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
            $Filter = "{0} and customerId eq '{1}'" -f $Filter, $TenantFilter
            # create where-object scriptblock
            $IncludedTenantFilter = [scriptblock]::Create("`$_.customerId -eq '$TenantFilter'")
            $RelationshipFilter = " and customer/tenantId eq '$TenantFilter'"
        } else {
            $Filter = "{0} and defaultDomainName eq '{1}'" -f $Filter, $TenantFilter
            $IncludedTenantFilter = [scriptblock]::Create("`$_.defaultDomainName -eq '$TenantFilter'")
            $RelationshipFilter = ''
        }
    } else {
        $IncludedTenantFilter = [scriptblock]::Create('$true')
        $RelationshipFilter = ''
    }

    $IncludedTenantsCache = Get-CIPPAzDataTableEntity @TenantsTable -Filter $Filter

    if (($IncludedTenantsCache | Measure-Object).Count -eq 0 -and $TenantFilter -ne $env:TenantID) {
        $BuildRequired = $true
    }

    if ($CleanOld.IsPresent) {
        $GDAPRelationships = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships?`$filter=status eq 'active' and not startsWith(displayName,'MLT_')&`$select=customer,autoExtendDuration,endDateTime&`$top=300" -NoAuthCheck:$true
        $GDAPList = foreach ($Relationship in $GDAPRelationships) {
            [PSCustomObject]@{
                customerId      = $Relationship.customer.tenantId
                displayName     = $Relationship.customer.displayName
                autoExtend      = ($Relationship.autoExtendDuration -ne 'PT0S')
                relationshipEnd = $Relationship.endDateTime
            }
        }
        $CurrentTenants = Get-CIPPAzDataTableEntity @TenantsTable -Filter "PartitionKey eq 'Tenants' and Excluded eq false"
        $CurrentTenants | Where-Object { $_.customerId -notin $GDAPList.customerId -and $_.customerId -ne $env:TenantID } | ForEach-Object {
            Remove-AzDataTableEntity -Force @TenantsTable -Entity $_
        }
    }
    $PartnerModeTable = Get-CippTable -tablename 'tenantMode'
    $PartnerTenantState = Get-CIPPAzDataTableEntity @PartnerModeTable

    if (($BuildRequired -or $TriggerRefresh.IsPresent) -and $PartnerTenantState.state -ne 'owntenant') {
        # Get TenantProperties table
        $PropertiesTable = Get-CippTable -TableName 'TenantProperties'
        if (!$env:RefreshToken) {
            throw 'RefreshToken not set. Cannot get tenant list.'
        }
        #get the full list of tenants
        $GDAPRelationships = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships?`$filter=status eq 'active' and not startsWith(displayName,'MLT_')$RelationshipFilter&`$select=customer,autoExtendDuration,endDateTime&`$top=300" -NoAuthCheck:$true
        $GDAPList = foreach ($Relationship in $GDAPRelationships) {
            [PSCustomObject]@{
                customerId      = $Relationship.customer.tenantId
                displayName     = $Relationship.customer.displayName
                autoExtend      = ($Relationship.autoExtendDuration -ne 'PT0S')
                relationshipEnd = $Relationship.endDateTime
            }
        }

        $ActiveRelationships = $GDAPList | Where-Object $IncludedTenantFilter | Where-Object { $_.customerId -notin $SkipListCache.customerId }
        $TenantList = $ActiveRelationships | Group-Object -Property customerId | ForEach-Object {

            # Write-Host (ConvertTo-Json -InputObject $_ -Depth 10)
            # Write-Host "Processing $($_.Name), $($_.displayName) to add to tenant list."
            $ExistingTenantInfo = Get-CIPPAzDataTableEntity @TenantsTable -Filter "PartitionKey eq 'Tenants' and RowKey eq '$($_.Name)'"

            $Alias = (Get-AzDataTableEntity @PropertiesTable -Filter "PartitionKey eq '$($_.Name)' and RowKey eq 'Alias'").Value

            if ($Alias) {
                Write-Host "Alias found for $($_.Name) - $Alias."
            }

            if ($TriggerRefresh.IsPresent -and $ExistingTenantInfo.customerId) {
                # Reset error count
                Write-Host "Resetting error count for $($_.Name)"
                $ExistingTenantInfo.GraphErrorCount = 0
                Add-CIPPAzDataTableEntity @TenantsTable -Entity $ExistingTenantInfo -Force | Out-Null
            }

            if ($ExistingTenantInfo -and $ExistingTenantInfo.RequiresRefresh -eq $false -and ($ExistingTenantInfo.displayName -eq $LatestRelationship.displayName -or $ExistingTenantInfo.displayName -eq $Alias)) {
                Write-Host 'Existing tenant found. We already have it cached, skipping.'

                $DisplayNameUpdated = $false
                if (![string]::IsNullOrEmpty($Alias)) {
                    if ($Alias -ne $ExistingTenantInfo.displayName) {
                        Write-Host "Alias found for $($_.Name)."
                        $ExistingTenantInfo.displayName = $Alias
                        $DisplayNameUpdated = $true
                    }
                } else {
                    if ($LatestRelationship.displayName -ne $ExistingTenantInfo.displayName) {
                        Write-Host 'Display name changed from relationship, updating.'
                        $ExistingTenantInfo.displayName = $LatestRelationship.displayName
                        $DisplayNameUpdated = $true
                    }
                }

                if ($DisplayNameUpdated) {
                    $ExistingTenantInfo.displayName = $LatestRelationship.displayName
                    Add-CIPPAzDataTableEntity @TenantsTable -Entity $ExistingTenantInfo -Force | Out-Null
                }

                $ExistingTenantInfo
                return
            }
            $LatestRelationship = $_.Group | Sort-Object -Property relationshipEnd | Select-Object -Last 1
            $AutoExtend = ($_.Group | Where-Object { $_.autoExtend -eq $true } | Measure-Object).Count -gt 0
            if (!$SkipDomains.IsPresent) {
                try {
                    Write-Host "Getting domains for $($_.Name)."
                    $Domains = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/domains?$top=999' -tenantid $LatestRelationship.customerId -NoAuthCheck:$true -ErrorAction Stop
                    $defaultDomainName = ($Domains | Where-Object { $_.isDefault -eq $true }).id
                    $initialDomainName = ($Domains | Where-Object { $_.isInitial -eq $true }).id
                } catch {
                    try {
                        #doing alternative method to temporarily get domains. Nightly refresh will fix this as it will be marked for renew.
                        Write-Host 'Main method failed, trying alternative method.'
                        Write-Host "Domain variable is $Domain"
                        $Domain = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/tenantRelationships/findTenantInformationByTenantId(tenantId='$($LatestRelationship.customerId)')" -NoAuthCheck:$true ).defaultDomainName
                        Write-Host "Alternative method worked, got domain $Domain."
                        $RequiresRefresh = $true
                    } catch {
                        $ErrorMessage = Get-CippException -Exception $_
                        Write-LogMessage -API 'Get-Tenants' -message "Tried adding $($LatestRelationship.customerId) to tenant list but failed to get domains - $($_.Exception.Message)" -Sev 'Critical' -LogData $ErrorMessage
                        $Domain = 'Invalid'
                    } finally {
                        $defaultDomainName = $Domain
                        $initialDomainName = $Domain
                    }
                }
                Write-Host 'finished getting domain'

                if (![string]::IsNullOrEmpty($Alias)) {
                    Write-Information "Setting display name to $Alias."
                    $displayName = $Alias
                } else {
                    $displayName = $LatestRelationship.displayName
                }

                $Obj = [PSCustomObject]@{
                    PartitionKey             = 'Tenants'
                    RowKey                   = $_.Name
                    customerId               = $_.Name
                    displayName              = $displayName
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
                if ($Obj.defaultDomainName -eq 'Invalid' -or !$Obj.defaultDomainName) {
                    Write-Host "We're skipping $($Obj.displayName) as it has an invalid default domain name. Something is up with this instance."
                    return
                }
                Write-Host "Adding $($_.Name) to tenant list."
                Add-CIPPAzDataTableEntity @TenantsTable -Entity $Obj -Force | Out-Null

                $Obj
            }
        }
        $IncludedTenantsCache = [system.collections.generic.list[object]]::new()
        if ($PartnerTenantState.state -eq 'PartnerTenantAvailable') {
            # Add partner tenant if env is set
            $Domains = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/domains?$top=999' -tenantid $env:TenantID -NoAuthCheck:$true
            $PartnerTenant = [PSCustomObject]@{
                RowKey            = $env:TenantID
                PartitionKey      = 'Tenants'
                customerId        = $env:TenantID
                defaultDomainName = ($Domains | Where-Object { $_.isDefault -eq $true }).id
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
            }
            $IncludedTenantsCache.Add($PartnerTenant)
            Add-AzDataTableEntity @TenantsTable -Entity $PartnerTenant -Force | Out-Null

        }
        foreach ($Tenant in $TenantList) {
            if ($Tenant.defaultDomainName -eq 'Invalid' -or [string]::IsNullOrWhiteSpace($Tenant.defaultDomainName)) {
                Write-LogMessage -API 'Get-Tenants' -message "We're skipping $($Tenant.displayName) as it has an invalid default domain name. Something is up with this instance." -level 'Critical'
                continue
            }
            $IncludedTenantsCache.Add($Tenant)
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
    return $IncludedTenantsCache | Where-Object { ($null -ne $_.defaultDomainName -and ($_.defaultDomainName -notmatch 'Domain Error' -or $IncludeAll.IsPresent)) } | Where-Object $IncludedTenantFilter | Sort-Object -Property displayName
}
