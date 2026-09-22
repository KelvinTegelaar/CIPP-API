
function Get-Tenants {
    <#
    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding(DefaultParameterSetName = 'Standard')]
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
        $SafeTenantFilter = ConvertTo-CIPPODataFilterValue -Value $TenantFilter -Type String

        if ($SafeTenantFilter -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
            $Filter = "{0} and customerId eq '{1}'" -f $Filter, $SafeTenantFilter
            # create where-object scriptblock
            $IncludedTenantFilter = [scriptblock]::Create("`$_.customerId -eq '$SafeTenantFilter'")
            $RelationshipFilter = " and customer/tenantId eq '$SafeTenantFilter'"
        } else {
            # parens: OData 'and' binds tighter than 'or', which would leave the initialDomainName clause unscoped
            $Filter = "{0} and (defaultDomainName eq '{1}' or initialDomainName eq '{1}')" -f $Filter, $SafeTenantFilter
            $IncludedTenantFilter = [scriptblock]::Create("`$_.defaultDomainName -eq '$SafeTenantFilter' -or `$_.initialDomainName -eq '$SafeTenantFilter'")
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
        try {
            $GDAPRelationships = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships?`$filter=status eq 'active'&`$select=customer,autoExtendDuration,endDateTime" -NoAuthCheck:$true
            # Filter out MLT relationships locally
            $GDAPRelationships = $GDAPRelationships | Where-Object { $_.displayName -notlike 'MLT_*' }
            if (!$GDAPRelationships) {
                Write-LogMessage -API 'Get-Tenants' -message 'Tried cleaning old tenants but failed to get GDAP relationships - No relationships returned' -Sev 'Critical'
                throw 'Failed to get GDAP relationships for cleaning old tenants.'
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'Get-Tenants' -message "Tried cleaning old tenants but failed to get GDAP relationships - $($_.Exception.Message)" -Sev 'Critical' -LogData $ErrorMessage
            throw $_
        }
        $GDAPList = foreach ($Relationship in $GDAPRelationships) {
            [PSCustomObject]@{
                customerId      = $Relationship.customer.tenantId
                displayName     = $Relationship.customer.displayName
                autoExtend      = ($Relationship.autoExtendDuration -ne 'PT0S')
                relationshipEnd = $Relationship.endDateTime
            }
        }
        $CurrentTenants = Get-CIPPAzDataTableEntity @TenantsTable -Filter "PartitionKey eq 'Tenants' and Excluded eq false and delegatedPrivilegeStatus ne 'directTenant'"
        $CurrentTenants | Where-Object { $_.customerId -notin $GDAPList.customerId -and $_.customerId -ne $env:TenantID } | ForEach-Object {
            Remove-CIPPAzDataTableEntity -Force @TenantsTable -Entity $_
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
        # GDAP relationship objects carry customerId, not domains, so a domain-scoped refresh must key
        # on the customerId of the row already read above - otherwise it matches zero relationships.
        $ResolvedCustomerId = ($IncludedTenantsCache | Select-Object -First 1).customerId
        if ($TenantFilter -and -not $RelationshipFilter -and $ResolvedCustomerId) {
            $RelationshipFilter = " and customer/tenantId eq '$ResolvedCustomerId'"
            $IncludedTenantFilter = [scriptblock]::Create("`$_.customerId -eq '$ResolvedCustomerId'")
        }
        #get the full list of tenants
        $GDAPRelationships = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/tenantRelationships/delegatedAdminRelationships?`$filter=status eq 'active'$RelationshipFilter&`$select=customer,autoExtendDuration,endDateTime" -NoAuthCheck:$true
        # Filter out MLT relationships locally
        $GDAPRelationships = $GDAPRelationships | Where-Object { $_.displayName -notlike 'MLT_*' }
        Write-Host "GDAP relationships found: $($GDAPRelationships.Count)"
        Write-Information "GDAP relationships found: $($GDAPRelationships.Count)"
        $totalTenants = $GDAPRelationships.customer.tenantId | Select-Object -Unique
        Write-Information "Total tenants found in relationships result: $($totalTenants.count)"
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

            # Reset per tenant so a fallback on one tenant does not leak RequiresRefresh onto the next.
            $RequiresRefresh = $false

            # Resolved before the cache-hit check below, which compares against its displayName.
            $LatestRelationship = $_.Group | Sort-Object -Property relationshipEnd | Select-Object -Last 1

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

            # Re-read domains for a row last derived over 7 days ago even when it looks healthy: a custom
            # domain can be made default in M365 after onboarding with nothing here to signal it, and the
            # cache-hit branch below never re-reads domains. LastRefresh is stamped only on a real fetch.
            # (Table returns a DateTimeOffset; [datetime] cannot cast it. Null/garbage throws -> stale.)
            try { $DomainsStale = ([DateTimeOffset]$ExistingTenantInfo.LastRefresh) -lt [DateTimeOffset]::UtcNow.AddDays(-7) } catch { $DomainsStale = $true }

            # A refresh scoped to one tenant is an explicit "re-read this one now" - never shortcut it.
            if ($ExistingTenantInfo -and $ExistingTenantInfo.RequiresRefresh -eq $false -and -not $DomainsStale -and -not ($TriggerRefresh.IsPresent -and $TenantFilter) -and ($ExistingTenantInfo.displayName -eq $LatestRelationship.displayName -or $ExistingTenantInfo.displayName -eq $Alias)) {
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
                    } catch {
                        $ErrorMessage = Get-CippException -Exception $_
                        Write-LogMessage -API 'Get-Tenants' -message "Tried adding $($LatestRelationship.customerId) to tenant list but failed to get domains - $($_.Exception.Message)" -Sev 'Critical' -LogData $ErrorMessage
                        $Domain = 'Invalid'
                    } finally {
                        # Main read failed, so this value is provisional - always flag for retry. The fallback returns
                        # the initial (.onmicrosoft.com) domain for many tenants: keep a good cached custom default over it.
                        $RequiresRefresh = $true
                        $KeepCached = $ExistingTenantInfo.defaultDomainName -and $ExistingTenantInfo.defaultDomainName -notlike '*.onmicrosoft.com'
                        $defaultDomainName = if ($KeepCached) { $ExistingTenantInfo.defaultDomainName } else { $Domain }
                        $initialDomainName = if ($KeepCached) { $ExistingTenantInfo.initialDomainName } else { $Domain }
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

    # Limit tenant list to allowed tenants if set in script scope from New-CippCoreRequest.
    # $null means unrestricted; any non-null scope filters, so a restricted caller whose scope
    # resolved to zero tenants gets an empty list back rather than every tenant (an empty array
    # is falsy, so a plain truthiness check would silently skip the narrowing).
    if ($script:CippAllowedTenantsStorage -and $null -ne $script:CippAllowedTenantsStorage.Value) {
        $IncludedTenantsCache = $IncludedTenantsCache | Where-Object { $script:CippAllowedTenantsStorage.Value -contains $_.customerId }
    }

    return $IncludedTenantsCache | Where-Object { ($null -ne $_.defaultDomainName -and ($_.defaultDomainName -notmatch 'Domain Error' -or $IncludeAll.IsPresent)) } | Where-Object $IncludedTenantFilter | Sort-Object -Property displayName
}
