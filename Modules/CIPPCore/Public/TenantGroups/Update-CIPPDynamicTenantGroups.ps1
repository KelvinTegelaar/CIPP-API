function Update-CIPPDynamicTenantGroups {
    <#
    .SYNOPSIS
        Update dynamic tenant groups based on their rules
    .DESCRIPTION
        This function processes dynamic tenant group rules and updates membership accordingly
    .PARAMETER GroupId
        The specific group ID to update. If not provided, all dynamic groups will be updated
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$GroupId
    )

    try {
        $GroupTable = Get-CippTable -tablename 'TenantGroups'
        $MembersTable = Get-CippTable -tablename 'TenantGroupMembers'
        $LicenseCacheTable = Get-CippTable -tablename 'cachetenantskus'

        $Skus = Get-CIPPAzDataTableEntity @LicenseCacheTable -Filter "PartitionKey eq 'sku' and Timestamp ge datetime'$( (Get-Date).ToUniversalTime().AddHours(-8).ToString('yyyy-MM-ddTHH:mm:ssZ') )'"

        $SkuHashtable = @{}
        foreach ($Sku in $Skus) {
            if ($Sku.JSON -and (Test-Json -Json $Sku.JSON -ErrorAction SilentlyContinue)) {
                $SkuHashtable[$Sku.RowKey] = $Sku.JSON | ConvertFrom-Json
            }
        }

        if ($GroupId) {
            $DynamicGroups = Get-CIPPAzDataTableEntity @GroupTable -Filter "PartitionKey eq 'TenantGroup' and RowKey eq '$GroupId'"
        } else {
            $DynamicGroups = Get-CIPPAzDataTableEntity @GroupTable -Filter "PartitionKey eq 'TenantGroup' and GroupType eq 'dynamic'"
        }

        if (-not $DynamicGroups) {
            Write-LogMessage -API 'TenantGroups' -message 'No dynamic groups found to process' -sev Info
            return @{ MembersAdded = 0; MembersRemoved = 0; GroupsProcessed = 0 }
        }

        $AllTenants = Get-Tenants -IncludeErrors
        $TotalMembersAdded = 0
        $TotalMembersRemoved = 0
        $GroupsProcessed = 0

        # Pre-load tenant group memberships for tenantGroupMember rules
        # This creates a cache to avoid repeated table queries during rule evaluation
        $script:TenantGroupMembersCache = @{}
        $AllGroupMembers = Get-CIPPAzDataTableEntity @MembersTable -Filter "PartitionKey eq 'Member'"
        foreach ($Member in $AllGroupMembers) {
            if (-not $script:TenantGroupMembersCache.ContainsKey($Member.GroupId)) {
                $script:TenantGroupMembersCache[$Member.GroupId] = [system.collections.generic.list[string]]::new()
            }
            $script:TenantGroupMembersCache[$Member.GroupId].Add($Member.customerId)
        }        foreach ($Group in $DynamicGroups) {
            try {
                Write-LogMessage -API 'TenantGroups' -message "Processing dynamic group: $($Group.Name)" -sev Info
                $Rules = @($Group.DynamicRules | ConvertFrom-Json)
                # Build a single Where-Object string for AND logic
                $WhereConditions = foreach ($Rule in $Rules) {
                    $Property = $Rule.property
                    $Operator = $Rule.operator
                    $Value = $Rule.value

                    switch ($Property) {
                        'delegatedAccessStatus' {
                            "`$_.delegatedPrivilegeStatus -$Operator '$($Value.value)'"
                        }
                        'availableLicense' {
                            if ($Operator -in @('in', 'notin')) {
                                $arrayValues = if ($Value -is [array]) { $Value.guid } else { @($Value.guid) }
                                $arrayAsString = $arrayValues | ForEach-Object { "'$_'" }
                                if ($Operator -eq 'in') {
                                    "(`$_.skuId | Where-Object { `$_ -in @($($arrayAsString -join ', ')) }).Count -gt 0"
                                } else {
                                    "(`$_.skuId | Where-Object { `$_ -in @($($arrayAsString -join ', ')) }).Count -eq 0"
                                }
                            } else {
                                "`$_.skuId -$Operator '$($Value.guid)'"
                            }
                        }
                        'availableServicePlan' {
                            if ($Operator -in @('in', 'notin')) {
                                $arrayValues = if ($Value -is [array]) { $Value.value } else { @($Value.value) }
                                $arrayAsString = $arrayValues | ForEach-Object { "'$_'" }
                                if ($Operator -eq 'in') {
                                    # Keep tenants with ANY of the provided plans
                                    "(`$_.servicePlans | Where-Object { `$_ -in @($($arrayAsString -join ', ')) }).Count -gt 0"
                                } else {
                                    # Exclude tenants with ANY of the provided plans
                                    "(`$_.servicePlans | Where-Object { `$_ -in @($($arrayAsString -join ', ')) }).Count -eq 0"
                                }
                            } else {
                                "`$_.servicePlans -$Operator '$($Value.value)'"
                            }
                        }
                        'tenantGroupMember' {
                            # Get members of the referenced tenant group
                            $ReferencedGroupId = $Value.value
                            if ($Operator -eq 'in') {
                                "`$_.customerId -in `$script:TenantGroupMembersCache['$ReferencedGroupId']"
                            } else {
                                "`$_.customerId -notin `$script:TenantGroupMembersCache['$ReferencedGroupId']"
                            }
                        }
                        'customVariable' {
                            # Custom variable matching - value contains variable name and expected value
                            # Handle case where variableName might be an object (autocomplete option) or a string
                            $VariableName = if ($Value.variableName -is [string]) {
                                $Value.variableName
                            } elseif ($Value.variableName.value) {
                                $Value.variableName.value
                            } else {
                                $Value.variableName
                            }
                            $ExpectedValue = $Value.value
                            # Escape single quotes in expected value for the condition string
                            $EscapedExpectedValue = $ExpectedValue -replace "'", "''"

                            switch ($Operator) {
                                'eq' {
                                    "(`$_.customVariables.ContainsKey('$VariableName') -and `$_.customVariables['$VariableName'].Value -eq '$EscapedExpectedValue')"
                                }
                                'ne' {
                                    "(-not `$_.customVariables.ContainsKey('$VariableName') -or `$_.customVariables['$VariableName'].Value -ne '$EscapedExpectedValue')"
                                }
                                'like' {
                                    "(`$_.customVariables.ContainsKey('$VariableName') -and `$_.customVariables['$VariableName'].Value -like '*$EscapedExpectedValue*')"
                                }
                                'notlike' {
                                    "(-not `$_.customVariables.ContainsKey('$VariableName') -or `$_.customVariables['$VariableName'].Value -notlike '*$EscapedExpectedValue*')"
                                }
                            }
                        }
                        default {
                            Write-LogMessage -API 'TenantGroups' -message "Unknown property type: $Property" -sev Warning
                            $null
                        }
                    }

                }
                if (!$WhereConditions) {
                    throw 'Generating the conditions failed. The conditions seem to be empty.'
                }
                Write-Information "Generated where conditions: $($WhereConditions | ConvertTo-Json )"
                $TenantObj = $AllTenants | ForEach-Object {
                    if ($Rules.property -contains 'availableLicense') {
                        if ($SkuHashtable.ContainsKey($_.customerId)) {
                            Write-Information "Using cached licenses for tenant $($_.defaultDomainName)"
                            $LicenseInfo = $SkuHashtable[$_.customerId]
                        } else {
                            Write-Information "Fetching licenses for tenant $($_.defaultDomainName)"
                            try {
                                $LicenseInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/subscribedSkus' -TenantId $_.defaultDomainName
                                # Cache the result
                                $CacheEntity = @{
                                    PartitionKey = 'sku'
                                    RowKey       = [string]$_.customerId
                                    JSON         = [string]($LicenseInfo | ConvertTo-Json -Depth 5 -Compress)
                                }
                                Add-CIPPAzDataTableEntity @LicenseCacheTable -Entity $CacheEntity -Force
                            } catch {
                                Write-LogMessage -API 'TenantGroups' -message 'Error getting licenses' -Tenant $_.defaultDomainName -sev Warning -LogData (Get-CippException -Exception $_)
                            }
                        }
                    }

                    # Fetch custom variables for this tenant if any rules use customVariable
                    $TenantVariables = @{}
                    if ($Rules.property -contains 'customVariable') {
                        try {
                            $TenantVariables = Get-CIPPTenantVariables -TenantFilter $_.customerId -IncludeGlobal
                        } catch {
                            Write-Information "Error fetching custom variables for tenant $($_.defaultDomainName): $($_.Exception.Message)"
                            Write-LogMessage -API 'TenantGroups' -message 'Error getting tenant variables' -Tenant $_.defaultDomainName -sev Warning -LogData (Get-CippException -Exception $_)
                        }
                    }

                    try {
                        $SKUId = $LicenseInfo.SKUId ?? @()
                        $ServicePlans = (Get-CIPPTenantCapabilities -TenantFilter $_.defaultDomainName).psobject.properties.name
                    } catch {
                        Write-Information "Error fetching capabilities for tenant $($_.defaultDomainName): $($_.Exception.Message)"
                        Write-LogMessage -API 'TenantGroups' -message 'Error getting tenant capabilities' -Tenant $_.defaultDomainName -sev Warning -LogData (Get-CippException -Exception $_)
                    }
                    [pscustomobject]@{
                        customerId               = $_.customerId
                        defaultDomainName        = $_.defaultDomainName
                        displayName              = $_.displayName
                        skuId                    = $SKUId
                        servicePlans             = $ServicePlans
                        delegatedPrivilegeStatus = $_.delegatedPrivilegeStatus
                        customVariables          = $TenantVariables
                    }
                }
                # Combine all conditions with the specified logic (AND or OR)
                $LogicOperator = if ($Group.RuleLogic -eq 'or') { ' -or ' } else { ' -and ' }
                $WhereString = $WhereConditions -join $LogicOperator
                Write-Information "Evaluating tenants with condition: $WhereString"
                Write-LogMessage -API 'TenantGroups' -message "Evaluating tenants for group '$($Group.Name)' with condition: $WhereString" -sev Info

                $ScriptBlock = [ScriptBlock]::Create($WhereString)
                $MatchingTenants = $TenantObj | Where-Object $ScriptBlock

                Write-Information "Found $($MatchingTenants.Count) matching tenants for group '$($Group.Name)'"

                $CurrentMembers = Get-CIPPAzDataTableEntity @MembersTable -Filter "PartitionKey eq 'Member' and GroupId eq '$($Group.RowKey)'"
                $CurrentMemberIds = $CurrentMembers.customerId
                $NewMemberIds = $MatchingTenants.customerId

                $ToAdd = $NewMemberIds | Where-Object { $_ -notin $CurrentMemberIds }
                $ToRemove = $CurrentMemberIds | Where-Object { $_ -notin $NewMemberIds }

                foreach ($TenantId in $ToAdd) {
                    $TenantInfo = $AllTenants | Where-Object { $_.customerId -eq $TenantId }
                    $MemberEntity = @{
                        PartitionKey = 'Member'
                        RowKey       = '{0}-{1}' -f $Group.RowKey, $TenantId
                        GroupId      = $Group.RowKey
                        customerId   = "$TenantId"
                    }
                    Add-CIPPAzDataTableEntity @MembersTable -Entity $MemberEntity -Force
                    Write-LogMessage -API 'TenantGroups' -message "Added tenant '$($TenantInfo.displayName)' to dynamic group '$($Group.Name)'" -sev Info
                    $TotalMembersAdded++
                }

                foreach ($TenantId in $ToRemove) {
                    $TenantInfo = $AllTenants | Where-Object { $_.customerId -eq $TenantId }
                    $MemberToRemove = $CurrentMembers | Where-Object { $_.customerId -eq $TenantId }
                    if ($MemberToRemove) {
                        Remove-AzDataTableEntity @MembersTable -Entity $MemberToRemove -Force
                        Write-LogMessage -API 'TenantGroups' -message "Removed tenant '$($TenantInfo.displayName)' from dynamic group '$($Group.Name)'" -sev Info
                        $TotalMembersRemoved++
                    }
                }

                $GroupsProcessed++
                Write-LogMessage -API 'TenantGroups' -message "Group '$($Group.Name)' updated: +$($ToAdd.Count) members, -$($ToRemove.Count) members" -sev Info

            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'TenantGroups' -message "Failed to process group '$($Group.Name)': $ErrorMessage" -sev Error
            }
        }

        Write-LogMessage -API 'TenantGroups' -message "Dynamic tenant group update completed. Groups processed: $GroupsProcessed, Members added: $TotalMembersAdded, Members removed: $TotalMembersRemoved" -sev Info

        return @{
            MembersAdded    = $TotalMembersAdded
            MembersRemoved  = $TotalMembersRemoved
            GroupsProcessed = $GroupsProcessed
        }

    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'TenantGroups' -message "Failed to update dynamic tenant groups: $ErrorMessage" -sev Error
        throw
    }
}

