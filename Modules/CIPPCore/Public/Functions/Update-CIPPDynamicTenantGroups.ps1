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

        foreach ($Group in $DynamicGroups) {
            try {
                Write-LogMessage -API 'TenantGroups' -message "Processing dynamic group: $($Group.Name)" -sev Info
                $Rules = $Group.DynamicRules | ConvertFrom-Json
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
                                "(`$_.skuId | Where-Object { `$_ -in @($($arrayAsString -join ', ')) }).Count -gt 0"
                            } else {
                                "`$_.skuId -contains '$($Value.guid)'"
                            }
                        }
                        'availableServicePlan' {
                            if ($Operator -in @('in', 'notin')) {
                                $arrayValues = if ($Value -is [array]) { $Value.value } else { @($Value.value) }
                                $arrayAsString = $arrayValues | ForEach-Object { "'$_'" }
                                "(`$_.servicePlans | Where-Object { `$_ -in @($($arrayAsString -join ', ')) }).Count -gt 0"
                            } else {
                                "`$_.servicePlans -contains '$($Value.value)'"
                            }
                        }
                        default {
                            Write-LogMessage -API 'TenantGroups' -message "Unknown property type: $Property" -sev Warning
                            $null
                        }
                    }

                }
                $TenantObj = $AllTenants | ForEach-Object {
                    $LicenseInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/subscribedSkus' -TenantId $_.defaultDomainName
                    $SKUId = $LicenseInfo.SKUId
                    $ServicePlans = (Get-CIPPTenantCapabilities -TenantFilter $_.defaultDomainName).psobject.properties.name
                    [pscustomobject]@{
                        customerId               = $_.customerId
                        defaultDomainName        = $_.defaultDomainName
                        displayName              = $_.displayName
                        skuId                    = $SKUId
                        servicePlans             = $ServicePlans
                        delegatedPrivilegeStatus = $_.delegatedPrivilegeStatus
                    }
                }
                # Combine all conditions with the specified logic (AND or OR)
                $LogicOperator = if ($Group.RuleLogic -eq 'or') { ' -or ' } else { ' -and ' }
                $WhereString = $WhereConditions -join $LogicOperator
                $ScriptBlock = [ScriptBlock]::Create($WhereString)
                $MatchingTenants = $TenantObj | Where-Object $ScriptBlock

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

