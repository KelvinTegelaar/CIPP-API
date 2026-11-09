
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

    if ($SkipList) {
        return Get-CIPPAzDataTableEntity @TenantsTable -Filter $ExcludedFilter
    }

    if ($IncludeAll.IsPresent) {
        $Filter = "PartitionKey eq 'Tenants'"
    } elseif ($IncludeErrors.IsPresent) {
        $Filter = "PartitionKey eq 'Tenants' and Excluded eq false"
    } else {
        $Filter = "PartitionKey eq 'Tenants' and Excluded eq false"
    }

    if ($TenantFilter) {
        #Write-Information "Getting tenant $TenantFilter"
        $SafeTenantFilter = ConvertTo-CIPPODataFilterValue -Value $TenantFilter -Type String

        if ($SafeTenantFilter -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
            $Filter = "{0} and customerId eq '{1}'" -f $Filter, $SafeTenantFilter
            $IncludedTenantFilter = { $_.customerId -eq $TenantFilter }
            $RelationshipFilter = " and customer/tenantId eq '$SafeTenantFilter'"
        } else {
            # parens: OData 'and' binds tighter than 'or', which would leave the initialDomainName clause unscoped
            $Filter = "{0} and (defaultDomainName eq '{1}' or initialDomainName eq '{1}')" -f $Filter, $SafeTenantFilter
            $IncludedTenantFilter = { $_.defaultDomainName -eq $TenantFilter -or $_.initialDomainName -eq $TenantFilter }
            $RelationshipFilter = ''
        }
    } else {
        $IncludedTenantFilter = { $true }
        $RelationshipFilter = ''
    }

    $IncludedTenantsCache = Get-CIPPAzDataTableEntity @TenantsTable -Filter $Filter

    # A miss on a domain (or 'AllTenants') can't be fixed by a rebuild: relationships carry no domains, so only a customerId miss can find a new tenant.
    if (($IncludedTenantsCache | Measure-Object).Count -eq 0 -and $TenantFilter -ne $env:TenantID -and (-not $TenantFilter -or $SafeTenantFilter -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')) {
        $BuildRequired = $true
    }

    if ($CleanOld.IsPresent) {
        # Only delete rows whose owning partner's relationship list was fetched successfully.
        $CleanPartners = @(Get-CIPPPartnerTenant)
        $CurrentTenants = Get-CIPPAzDataTableEntity @TenantsTable -Filter "PartitionKey eq 'Tenants' and Excluded eq false and delegatedPrivilegeStatus ne 'directTenant'"
        # Only check GDAP relationships if there are GDAP-managed tenants to reconcile against - direct-tenant deployments have none.
        if (($CurrentTenants | Measure-Object).Count -eq 0) { $CleanPartners = @() }
        foreach ($CleanPartner in $CleanPartners) {
            try {
                $GDAPRelationships = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships?`$filter=status eq 'active'&`$select=customer,autoExtendDuration,endDateTime" -tenantid $CleanPartner.RowKey -NoAuthCheck:$true
                # Filter out MLT relationships locally
                $GDAPRelationships = $GDAPRelationships | Where-Object { $_.displayName -notlike 'MLT_*' }
                if (!$GDAPRelationships) {
                    Write-LogMessage -API 'Get-Tenants' -message "Tried cleaning old tenants for partner $($CleanPartner.RowKey) but failed to get GDAP relationships - No relationships returned" -Sev 'Critical'
                    if ($CleanPartners.Count -eq 1) { throw 'Failed to get GDAP relationships for cleaning old tenants.' }
                    continue
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Get-Tenants' -message "Tried cleaning old tenants for partner $($CleanPartner.RowKey) but failed to get GDAP relationships - $($_.Exception.Message)" -Sev 'Critical' -LogData $ErrorMessage
                if ($CleanPartners.Count -eq 1) { throw $_ }
                continue
            }
            $ActiveCustomerIds = @($GDAPRelationships.customer.tenantId)
            $CurrentTenants | Where-Object {
                ($_.partnerTenantId -eq $CleanPartner.RowKey -or (!$_.partnerTenantId -and $CleanPartner.RowKey -eq $env:TenantID)) -and
                $_.customerId -notin $ActiveCustomerIds -and
                $_.customerId -notin $CleanPartners.RowKey
            } | ForEach-Object {
                Remove-CIPPAzDataTableEntity -Force @TenantsTable -Entity $_
            }
        }
    }
    if ($BuildRequired -or $TriggerRefresh.IsPresent -or $IncludedTenantsCache.RowKey.count -eq 0) {
        $PartnerModeTable = Get-CippTable -tablename 'tenantMode'
        $PartnerTenantState = Get-CIPPAzDataTableEntity @PartnerModeTable
    }

    if (($BuildRequired -or $TriggerRefresh.IsPresent) -and $PartnerTenantState.state -ne 'owntenant') {
        # Get TenantProperties table
        $PropertiesTable = Get-CippTable -TableName 'TenantProperties'
        if (!$env:RefreshToken) {
            throw 'RefreshToken not set. Cannot get tenant list.'
        }
        # GDAP relationship objects carry customerId, not domains, so a domain-scoped refresh must key
        # on the customerId of the row already read above - otherwise it matches zero relationships.
        $ResolvedCustomerId = @($IncludedTenantsCache)[0].customerId
        if ($TenantFilter -and -not $RelationshipFilter -and $ResolvedCustomerId) {
            $RelationshipFilter = " and customer/tenantId eq '$ResolvedCustomerId'"
            $IncludedTenantFilter = { $_.customerId -eq $ResolvedCustomerId }
        }

        $Partners = @(Get-CIPPPartnerTenant)

        # Bulk prefetch rows and aliases (2 queries instead of 2 per customer).
        $ExistingByCustomerId = @{}
        foreach ($Row in (Get-CIPPAzDataTableEntity @TenantsTable -Filter "PartitionKey eq 'Tenants'")) {
            $ExistingByCustomerId[$Row.RowKey] = $Row
        }
        $AliasById = @{}
        foreach ($AliasRow in (Get-AzDataTableEntity @PropertiesTable -Filter "RowKey eq 'Alias'")) {
            $AliasById[$AliasRow.PartitionKey] = $AliasRow.Value
        }

        $SkipListCache = Get-CIPPAzDataTableEntity @TenantsTable -Filter $ExcludedFilter

        # Enumerate relationships per partner, as that partner; a failed partner is skipped.
        $AllRelationships = foreach ($Partner in $Partners) {
            try {
                $GDAPRelationships = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/tenantRelationships/delegatedAdminRelationships?`$filter=status eq 'active'$RelationshipFilter&`$select=customer,autoExtendDuration,endDateTime" -tenantid $Partner.RowKey -NoAuthCheck:$true
                # Filter out MLT relationships locally
                $GDAPRelationships = $GDAPRelationships | Where-Object { $_.displayName -notlike 'MLT_*' }
                foreach ($Relationship in $GDAPRelationships) {
                    [PSCustomObject]@{
                        partnerTenantId = "$($Partner.RowKey)"
                        customerId      = $Relationship.customer.tenantId
                        displayName     = $Relationship.customer.displayName
                        autoExtend      = ($Relationship.autoExtendDuration -ne 'PT0S')
                        relationshipEnd = $Relationship.endDateTime
                    }
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Get-Tenants' -message "Failed to get GDAP relationships for partner tenant $($Partner.RowKey) - $($_.Exception.Message)" -Sev 'Critical' -LogData $ErrorMessage
                if ($Partners.Count -eq 1) { throw $_ }
            }
        }
        Write-Information "GDAP relationships found: $(($AllRelationships | Measure-Object).Count) across $($Partners.Count) partner tenant(s)"
        $totalTenants = $AllRelationships.customerId | Select-Object -Unique
        Write-Information "Total tenants found in relationships result: $($totalTenants.count)"

        # Partner tenants get partner rows, never customer rows.
        $ActiveRelationships = $AllRelationships | Where-Object $IncludedTenantFilter | Where-Object { $_.customerId -notin $SkipListCache.customerId -and $_.customerId -notin $Partners.RowKey }

        $NeedsDomainLookup = [System.Collections.Generic.List[object]]::new()
        $TenantList = foreach ($Group in ($ActiveRelationships | Group-Object -Property customerId)) {
            $LatestRelationship = $Group.Group | Sort-Object -Property relationshipEnd | Select-Object -Last 1
            $AutoExtend = ($Group.Group | Where-Object { $_.autoExtend -eq $true } | Measure-Object).Count -gt 0
            $KnownPartners = @($Group.Group.partnerTenantId | Sort-Object -Unique)
            $ExistingTenantInfo = $ExistingByCustomerId[$Group.Name]
            $Alias = $AliasById[$Group.Name]

            # Keep a still-valid existing owner (manual pins included); otherwise auto-assign.
            $ExistingOwner = $ExistingTenantInfo.partnerTenantId
            $AssignmentMode = if ($ExistingTenantInfo.partnerAssignmentMode) { $ExistingTenantInfo.partnerAssignmentMode } else { 'auto' }
            if ($ExistingOwner -and $KnownPartners -contains $ExistingOwner) {
                $Owner = $ExistingOwner
            } else {
                if ($AssignmentMode -eq 'manual' -and $ExistingOwner) {
                    Write-LogMessage -API 'Get-Tenants' -message "Manually assigned partner $ExistingOwner for tenant $($Group.Name) no longer has an active relationship - reverting to automatic assignment." -Sev 'Alert'
                }
                $AssignmentMode = 'auto'
                $Owner = if ($KnownPartners -contains "$env:TenantID") { "$env:TenantID" } else { $KnownPartners | Select-Object -First 1 }
                # A missing partnerTenantId means the primary partner owned the row.
                $PreviousOwner = if ($ExistingOwner) { $ExistingOwner } else { "$env:TenantID" }
                if ($ExistingTenantInfo -and $Owner -ne $PreviousOwner) {
                    # Tokens minted under the previous owner stay valid for ~1h otherwise.
                    $null = Clear-CippTokenCache -TenantFilter $Group.Name
                }
            }

            # Re-read domains for a row last derived over 7 days ago even when it looks healthy: a custom
            # domain can be made default in M365 after onboarding with nothing here to signal it, and the
            # cache-hit branch below never re-reads domains. LastRefresh is stamped only on a real fetch.
            # (Table returns a DateTimeOffset; [datetime] cannot cast it. Null/garbage throws -> stale.)
            try { $DomainsStale = ([DateTimeOffset]$ExistingTenantInfo.LastRefresh) -lt [DateTimeOffset]::UtcNow.AddDays(-7) } catch { $DomainsStale = $true }

            # A refresh scoped to one tenant is an explicit "re-read this one now" - never shortcut it.
            if ($ExistingTenantInfo -and $ExistingTenantInfo.RequiresRefresh -ne $true -and -not $DomainsStale -and -not ($TriggerRefresh.IsPresent -and $TenantFilter)) {
                # Cached row - update metadata only.
                $Updated = $false
                $TargetDisplayName = if (![string]::IsNullOrEmpty($Alias)) { $Alias } else { $LatestRelationship.displayName }
                if ($TargetDisplayName -and $ExistingTenantInfo.displayName -ne $TargetDisplayName) {
                    $ExistingTenantInfo.displayName = $TargetDisplayName
                    $Updated = $true
                }
                foreach ($Pair in @(
                        @{ Name = 'partnerTenantId'; Value = $Owner },
                        @{ Name = 'partnerAssignmentMode'; Value = $AssignmentMode },
                        @{ Name = 'knownPartners'; Value = ($KnownPartners -join ',') },
                        @{ Name = 'relationshipEnd'; Value = $LatestRelationship.relationshipEnd },
                        @{ Name = 'relationshipCount'; Value = $Group.Count },
                        @{ Name = 'hasAutoExtend'; Value = $AutoExtend }
                    )) {
                    if ("$($ExistingTenantInfo.($Pair.Name))" -ne "$($Pair.Value)") {
                        $ExistingTenantInfo | Add-Member -MemberType NoteProperty -Name $Pair.Name -Value $Pair.Value -Force
                        $Updated = $true
                    }
                }
                if ($Updated) {
                    Add-CIPPAzDataTableEntity @TenantsTable -Entity $ExistingTenantInfo -Force | Out-Null
                }
                $ExistingTenantInfo
                continue
            }

            if (!$SkipDomains.IsPresent) {
                $NeedsDomainLookup.Add([PSCustomObject]@{
                        customerId         = $Group.Name
                        partnerTenantId    = $Owner
                        assignmentMode     = $AssignmentMode
                        knownPartners      = ($KnownPartners -join ',')
                        displayName        = if (![string]::IsNullOrEmpty($Alias)) { $Alias } else { $LatestRelationship.displayName }
                        relationshipEnd    = $LatestRelationship.relationshipEnd
                        relationshipCount  = $Group.Count
                        hasAutoExtend      = $AutoExtend
                        existingInitial    = $ExistingTenantInfo.initialDomainName
                        existingDefault    = $ExistingTenantInfo.defaultDomainName
                    })
            }
        }

        # Batched domain lookup as each owning partner - never a per-tenant Graph loop here.
        # Results are provisional (no initialDomainName), so rows keep RequiresRefresh until
        # the per-tenant hydration activities complete.
        if ($NeedsDomainLookup.Count -gt 0) {
            $ResolvedInfo = @{}
            foreach ($PartnerGroup in ($NeedsDomainLookup | Group-Object -Property partnerTenantId)) {
                $BatchRequests = foreach ($Item in $PartnerGroup.Group) {
                    @{ id = "$($Item.customerId)"; method = 'GET'; url = "/tenantRelationships/findTenantInformationByTenantId(tenantId='$($Item.customerId)')" }
                }
                try {
                    $Responses = New-GraphBulkRequest -Requests @($BatchRequests) -tenantid $PartnerGroup.Name -NoAuthCheck $true -Version 'v1.0'
                    foreach ($Response in $Responses) {
                        if ($Response.body.defaultDomainName) {
                            $ResolvedInfo[$Response.id] = $Response.body
                        }
                    }
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    Write-LogMessage -API 'Get-Tenants' -message "Failed bulk tenant information lookup as partner $($PartnerGroup.Name) - $($_.Exception.Message)" -Sev 'Critical' -LogData $ErrorMessage
                }
            }
            $NewRows = foreach ($Item in $NeedsDomainLookup) {
                $Resolved = $ResolvedInfo[$Item.customerId]
                # The lookup returns the initial (.onmicrosoft.com) domain for many tenants: keep a good
                # cached custom default over it until the authoritative hydration lands.
                $KeepCached = $Item.existingDefault -and $Item.existingDefault -notlike '*.onmicrosoft.com'
                if (!$Resolved.defaultDomainName -and !$KeepCached) {
                    Write-LogMessage -API 'Get-Tenants' -message "Tried adding $($Item.customerId) to tenant list but failed to get its default domain." -Sev 'Critical'
                    continue
                }
                $DefaultDomainName = if ($KeepCached) { $Item.existingDefault } else { $Resolved.defaultDomainName }
                # The lookup only knows the default domain, which is a custom one for most tenants. Portal
                # links pass initialDomainName as delegatedOrg, so keep a cached .onmicrosoft.com one over it.
                $InitialDomainName = if ($Item.existingInitial -like '*.onmicrosoft.com') { $Item.existingInitial } else { $Resolved.defaultDomainName ?? $DefaultDomainName }
                New-CIPPTenantRow -Item $Item -DefaultDomainName $DefaultDomainName -InitialDomainName $InitialDomainName -RequiresRefresh $true
            }

            if (($NewRows | Measure-Object).Count -gt 0) {
                Add-CIPPAzDataTableEntity @TenantsTable -Entity @($NewRows) -Force | Out-Null
                $TenantList = @($TenantList) + @($NewRows)

                # Fan out per-tenant domain hydration (Push-UpdateTenantDomains).
                try {
                    $HydrationBatch = foreach ($Row in $NewRows) {
                        @{ FunctionName = 'UpdateTenantDomains'; customerId = "$($Row.customerId)" }
                    }
                    $InputObject = [PSCustomObject]@{
                        OrchestratorName = 'UpdateTenantDomainsOrchestrator'
                        Batch            = @($HydrationBatch)
                        SkipLog          = $true
                    }
                    $null = Start-CIPPOrchestrator -InputObject $InputObject
                    Write-Information "Queued domain hydration for $(($NewRows | Measure-Object).Count) tenant(s)."
                } catch {
                    Write-Information "Failed to queue tenant domain hydration - rows stay marked RequiresRefresh and the next refresh retries. $($_.Exception.Message)"
                }
            }
        }

        $IncludedTenantsCache = [system.collections.generic.list[object]]::new()
        if ($PartnerTenantState.state -eq 'PartnerTenantAvailable') {
            # One partner row per configured partner. With multiple partners each row is
            # suffixed with its org name; a single partner keeps the classic label.
            $MultiPartnerEnabled = (Get-CIPPFeatureFlag -Id 'MultiPartner').Enabled -eq $true
            foreach ($Partner in $Partners) {
                # Managed=false hides the partner from the tenant list
                if ($Partner.Managed -eq $false) { continue }
                try {
                    $PartnerOrg = (New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/organization?$select=displayName,verifiedDomains' -tenantid $Partner.RowKey -NoAuthCheck:$true -ErrorAction Stop) | Select-Object -First 1
                } catch {
                    Write-LogMessage -API 'Get-Tenants' -message "Failed to get organization info for partner tenant $($Partner.RowKey) - $($_.Exception.Message)" -Sev 'Critical' -LogData (Get-CippException -Exception $_)
                    continue
                }
                $OrgName = $PartnerOrg.displayName ?? $Partner.displayName
                $PartnerDisplayName = if ($Partners.Count -gt 1 -and $OrgName) { "*Partner Tenant ($OrgName)" } else { '*Partner Tenant' }
                $PartnerDefaultDomain = ($PartnerOrg.verifiedDomains | Where-Object { $_.isDefault -eq $true }).name
                $PartnerTenant = [PSCustomObject]@{
                    RowKey             = $Partner.RowKey
                    PartitionKey       = 'Tenants'
                    customerId         = $Partner.RowKey
                    defaultDomainName  = $PartnerDefaultDomain
                    initialDomainName  = ($PartnerOrg.verifiedDomains | Where-Object { $_.isInitial -eq $true }).name
                    displayName        = $PartnerDisplayName
                    domains            = 'PartnerTenant'
                    partnerTenantId    = "$($Partner.RowKey)"
                    isPartnerTenantRow = $true
                    Excluded           = $false
                    ExcludeUser        = ''
                    ExcludeDate        = ''
                    LastGraphError     = ''
                    RequiresRefresh    = $false
                    LastRefresh        = (Get-Date).ToUniversalTime()
                }
                $IncludedTenantsCache.Add($PartnerTenant)
                Add-AzDataTableEntity @TenantsTable -Entity $PartnerTenant -Force | Out-Null

                # Keep the PartnerTenants row's name/domain current for the settings page
                if ($MultiPartnerEnabled -and $OrgName -and ($Partner.displayName -ne $OrgName -or $Partner.defaultDomainName -ne $PartnerDefaultDomain)) {
                    $PartnerTable = Get-CippTable -tablename 'PartnerTenants'
                    $Partner | Add-Member -MemberType NoteProperty -Name 'displayName' -Value "$OrgName" -Force
                    $Partner | Add-Member -MemberType NoteProperty -Name 'defaultDomainName' -Value "$PartnerDefaultDomain" -Force
                    $null = Add-CIPPAzDataTableEntity @PartnerTable -Entity ($Partner | Select-Object -Property * -ExcludeProperty IsPrimary) -Force
                }
            }
        }
        foreach ($Tenant in $TenantList) {
            if ($Tenant.defaultDomainName -eq 'Invalid' -or [string]::IsNullOrWhiteSpace($Tenant.defaultDomainName)) {
                Write-LogMessage -API 'Get-Tenants' -message "We're skipping $($Tenant.displayName) as it has an invalid default domain name. Something is up with this instance." -sev 'Critical'
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
                LastGraphError    = ''
                RequiresRefresh   = [bool]$RequiresRefresh
                LastRefresh       = (Get-Date).ToUniversalTime()
            })
        if ($IncludedTenantsCache) {
            Add-CIPPAzDataTableEntity @TenantsTable -Entity $IncludedTenantsCache -Force | Out-Null
        }
    }

    # Rows can only carry a non-primary owner if MultiPartner was enabled at some point, so the
    # flag is only read when one is present. With the flag off those tenants are hidden rather
    # than returned to a single-partner code path; the rows stay in the table and come back when
    # the flag is re-enabled. An empty partnerTenantId means the primary partner.
    $NonPrimaryOwned = @($IncludedTenantsCache | Where-Object { $_.partnerTenantId -and $_.partnerTenantId -ne $env:TenantID })
    if ($NonPrimaryOwned.Count -gt 0 -and (Get-CIPPFeatureFlag -Id 'MultiPartner').Enabled -ne $true) {
        $IncludedTenantsCache = $IncludedTenantsCache | Where-Object { -not $_.partnerTenantId -or $_.partnerTenantId -eq $env:TenantID }
    }

    # Limit tenant list to allowed tenants if set in script scope from New-CippCoreRequest.
    # $null means unrestricted; any non-null scope filters, so a restricted caller whose scope
    # resolved to zero tenants gets an empty list back rather than every tenant (an empty array
    # is falsy, so a plain truthiness check would silently skip the narrowing).
    $Scoped = $script:CippAllowedTenantsStorage -and $null -ne $script:CippAllowedTenantsStorage.Value
    $Tenants = foreach ($Tenant in $IncludedTenantsCache) {
        if ($Scoped -and $script:CippAllowedTenantsStorage.Value -notcontains $Tenant.customerId) { continue }
        if ($null -ne $Tenant.defaultDomainName -and ($Tenant.defaultDomainName -notmatch 'Domain Error' -or $IncludeAll.IsPresent)) { $Tenant }
    }
    if ($TenantFilter) { $Tenants = @($Tenants).Where($IncludedTenantFilter) }
    if (@($Tenants).Count -le 1) { return $Tenants }
    return $Tenants | Sort-Object -Property displayName
}
