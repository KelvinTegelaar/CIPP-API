function Invoke-ListJITAdmin {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Role.Read

    .DESCRIPTION
        List Just-in-time admin users for a tenant or all tenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)


    $Schema = Get-CIPPSchemaExtensions | Where-Object { $_.id -match '_cippUser' } | Select-Object -First 1
    $TenantFilter = $Request.Query.TenantFilter

    if ($TenantFilter -ne 'AllTenants') {
        # Single tenant logic
        $BulkRequests = [System.Collections.Generic.List[object]]::new()
        $BulkRequests.Add(@{
                id     = 'users'
                method = 'GET'
                url    = "users?`$count=true&`$select=id,accountEnabled,displayName,userPrincipalName,$($Schema.id)&`$filter=$($Schema.id)/jitAdminEnabled eq true or $($Schema.id)/jitAdminEnabled eq false&`$top=999"
            })

        $BulkResults = New-GraphBulkRequest -tenantid $TenantFilter -Requests $BulkRequests
        $Users = ($BulkResults | Where-Object { $_.id -eq 'users' }).body.value | Where-Object { $_.id }

        $BulkRequests.Clear()
        foreach ($User in $Users) {
            $BulkRequests.Add(@{
                    id     = $User.id
                    method = 'GET'
                    url    = "users/$($User.id)/memberOf/microsoft.graph.directoryRole/?`$select=id,displayName"
                })
        }
        $RoleResults = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($BulkRequests)
        # Write-Information ($RoleResults | ConvertTo-Json -Depth 10 )
        $Results = $Users | ForEach-Object {
            $MemberOf = ($RoleResults | Where-Object -Property id -EQ $_.id).body.value | Select-Object displayName, id
            [PSCustomObject]@{
                id                 = $_.id
                displayName        = $_.displayName
                userPrincipalName  = $_.userPrincipalName
                accountEnabled     = $_.accountEnabled
                jitAdminEnabled    = $_.($Schema.id).jitAdminEnabled
                jitAdminExpiration = $_.($Schema.id).jitAdminExpiration
                jitAdminStartDate  = $_.($Schema.id).jitAdminStartDate
                jitAdminReason     = $_.($Schema.id).jitAdminReason
                jitAdminCreatedBy  = $_.($Schema.id).jitAdminCreatedBy
                memberOf           = $MemberOf
            }
        }

        # Write-Information ($Results | ConvertTo-Json -Depth 10)
        $Metadata = [PSCustomObject]@{Method = 'BulkRequest' }
    } else {
        # AllTenants logic
        $Results = [System.Collections.Generic.List[object]]::new()
        $Metadata = @{}
        $Table = Get-CIPPTable -TableName CacheJITAdmin
        $PartitionKey = 'JITAdminUser'
        $Filter = "PartitionKey eq '$PartitionKey'"
        $Rows = Get-CIPPAzDataTableEntity @Table -filter $Filter | Where-Object -Property Timestamp -GT (Get-Date).AddMinutes(-60)

        $QueueReference = '{0}-{1}' -f $TenantFilter, $PartitionKey # $TenantFilter is 'AllTenants'
        Write-Information "QueueReference: $QueueReference"
        $RunningQueue = Invoke-ListCippQueue -Reference $QueueReference | Where-Object { $_.Status -notmatch 'Completed' -and $_.Status -notmatch 'Failed' }

        if ($RunningQueue) {
            $Metadata = [PSCustomObject]@{
                QueueMessage = 'Still loading JIT Admin data for all tenants. Please check back in a few more minutes.'
                QueueId      = $RunningQueue.RowKey
            }
        } elseif (!$Rows -and !$RunningQueue) {
            $TenantList = Get-Tenants -IncludeErrors
            $Queue = New-CippQueueEntry -Name 'JIT Admin List - All Tenants' -Link '/identity/administration/jit-admin?tenantFilter=AllTenants' -Reference $QueueReference -TotalTasks ($TenantList | Measure-Object).Count

            $Metadata = [PSCustomObject]@{
                QueueMessage = 'Loading JIT Admin data for all tenants. Please check back in a few minutes.'
                QueueId      = $Queue.RowKey
            }
            $InputObject = [PSCustomObject]@{
                OrchestratorName = 'JITAdminOrchestrator'
                QueueFunction    = @{
                    FunctionName = 'GetTenants'
                    QueueId      = $Queue.RowKey
                    TenantParams = @{
                        IncludeErrors = $true
                    }
                    DurableName  = 'ExecJITAdminListAllTenants'
                }
                SkipLog          = $true
            }
            Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
        } else {
            $Metadata = [PSCustomObject]@{
                QueueId = $RunningQueue.RowKey ?? $null
            }
            # There is data in the cache, so we will use that
            Write-Information "Found $($Rows.Count) rows in the cache"
            foreach ($row in $Rows) {
                $UserObject = $row.JITAdminUser | ConvertFrom-Json
                $Results.Add(
                    [PSCustomObject]@{
                        Tenant             = $row.Tenant
                        id                 = $UserObject.id
                        displayName        = $UserObject.displayName
                        userPrincipalName  = $UserObject.userPrincipalName
                        accountEnabled     = $UserObject.accountEnabled
                        jitAdminEnabled    = $UserObject.jitAdminEnabled
                        jitAdminExpiration = $UserObject.jitAdminExpiration
                        jitAdminStartDate  = $UserObject.jitAdminStartDate
                        jitAdminReason     = $UserObject.jitAdminReason
                        jitAdminCreatedBy  = $UserObject.jitAdminCreatedBy
                        memberOf           = $UserObject.memberOf
                    }
                )
            }
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{
                Results  = @($Results)
                Metadata = $Metadata
            }
        })
}
