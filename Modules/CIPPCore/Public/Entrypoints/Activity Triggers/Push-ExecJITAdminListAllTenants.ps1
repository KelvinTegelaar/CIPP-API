function Push-ExecJITAdminListAllTenants {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Tenant = Get-Tenants -TenantFilter $Item.customerId
    $DomainName = $Tenant.defaultDomainName
    $Table = Get-CIPPTable -TableName CacheJITAdmin

    try {
        # Get schema extensions
        $Schema = Get-CIPPSchemaExtensions | Where-Object { $_.id -match '_cippUser' } | Select-Object -First 1

        # Query users with JIT Admin enabled
        $Query = @{
            TenantFilter = $DomainName # Use $DomainName for the current tenant
            Endpoint     = 'users'
            Parameters   = @{
                '$count'  = 'true'
                '$select' = "id,accountEnabled,displayName,userPrincipalName,$($Schema.id)"
                '$filter' = "$($Schema.id)/jitAdminEnabled eq true or $($Schema.id)/jitAdminEnabled eq false" # Fetches both states to cache current status
            }
        }
        $Users = Get-GraphRequestList @Query | Where-Object { $_.id }

        if ($Users) {
            # Get role memberships
            $BulkRequests = $Users | ForEach-Object { @(
                    @{
                        id     = $_.id
                        method = 'GET'
                        url    = "users/$($_.id)/memberOf/microsoft.graph.directoryRole/?`$select=id,displayName"
                    }
                )
            }
            # Ensure $BulkRequests is not empty or null before making the bulk request
            if ($BulkRequests -and $BulkRequests.Count -gt 0) {
                $RoleResults = New-GraphBulkRequest -tenantid $DomainName -Requests @($BulkRequests)

                # Format the data
                $Results = $Users | ForEach-Object {
                    $currentUser = $_ # Capture current user in the loop
                    $MemberOf = @() # Initialize as empty array
                    if ($RoleResults) {
                        $userRoleResult = $RoleResults | Where-Object -Property id -EQ $currentUser.id
                        if ($userRoleResult -and $userRoleResult.body -and $userRoleResult.body.value) {
                            $MemberOf = $userRoleResult.body.value | Select-Object displayName, id
                        }
                    }

                    $jitAdminData = $currentUser.($Schema.id)
                    $jitAdminEnabled = if ($jitAdminData -and $jitAdminData.PSObject.Properties['jitAdminEnabled']) { $jitAdminData.jitAdminEnabled } else { $false }
                    $jitAdminExpiration = if ($jitAdminData -and $jitAdminData.PSObject.Properties['jitAdminExpiration']) { $jitAdminData.jitAdminExpiration } else { $null }

                    [PSCustomObject]@{
                        id                 = $currentUser.id
                        displayName        = $currentUser.displayName
                        userPrincipalName  = $currentUser.userPrincipalName
                        accountEnabled     = $currentUser.accountEnabled
                        jitAdminEnabled    = $jitAdminEnabled
                        jitAdminExpiration = $jitAdminExpiration
                        memberOf           = ($MemberOf | ConvertTo-Json -Depth 5 -Compress)
                    }
                }

                # Add to Azure Table
                foreach ($result in $Results) {
                    $GUID = (New-Guid).Guid
                    Write-Host ($result | ConvertTo-Json -Depth 10 -Compress)
                    $GraphRequest = @{
                        JITAdminUser = [string]($result | ConvertTo-Json -Depth 10 -Compress)
                        RowKey       = [string]$GUID
                        PartitionKey = 'JITAdminUser'
                        Tenant       = [string]$DomainName
                        UserId       = [string]$result.id # Add UserId for easier querying if needed
                        UserUPN      = [string]$result.userPrincipalName # Add UserUPN for easier querying
                    }
                    Add-CIPPAzDataTableEntity @Table -Entity $GraphRequest -Force | Out-Null
                }
            } else {
                # No users with JIT Admin attributes found, or no users at all
                Write-Host "No JIT Admin users or no users found to process for tenant $DomainName."
            }
        } else {
            Write-Host "No users found for tenant $DomainName."
        }

    } catch {
        $GUID = (New-Guid).Guid
        $ErrorMessage = "Could not process JIT Admin users for Tenant: $($DomainName). Error: $($_.Exception.Message)"
        if ($_.ScriptStackTrace) {
            $ErrorMessage += " StackTrace: $($_.ScriptStackTrace)"
        }
        $ErrorJson = ConvertTo-Json -InputObject @{
            Tenant    = $DomainName
            Error     = $ErrorMessage
            Exception = ($_.Exception.Message | ConvertTo-Json -Depth 3 -Compress)
            Timestamp = (Get-Date).ToString('s')
        }
        $GraphRequest = @{
            JITAdminUser = [string]$ErrorJson
            RowKey       = [string]$GUID
            PartitionKey = 'JITAdminUser'
            Tenant       = [string]$DomainName
        }
        Add-CIPPAzDataTableEntity @Table -Entity $GraphRequest -Force | Out-Null
        Write-Error ('Error processing JIT Admin for {0}: {1}' -f $DomainName, $_.Exception.Message)
    }
}
