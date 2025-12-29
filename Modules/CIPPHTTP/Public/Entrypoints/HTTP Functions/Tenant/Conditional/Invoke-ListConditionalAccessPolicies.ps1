function Invoke-ListConditionalAccessPolicies {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.ConditionalAccess.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    #Region Helper functions
    function Get-LocationNameFromId {
        [CmdletBinding()]
        param (
            [Parameter()]
            $ID,
            $Locations
        )
        if ($id -eq 'All') {
            return 'All'
        }
        $DisplayName = $Locations | Where-Object { $_.id -eq $ID } | Select-Object -ExpandProperty DisplayName
        if ([string]::IsNullOrEmpty($displayName)) {
            return  $ID
        } else {
            return $DisplayName
        }
    }

    function Get-RoleNameFromId {
        [CmdletBinding()]
        param (
            [Parameter()]
            $ID,
            $RoleDefinitions
        )
        if ($id -eq 'All') {
            return 'All'
        }
        $DisplayName = $RoleDefinitions | Where-Object { $_.id -eq $ID } | Select-Object -ExpandProperty DisplayName
        if ([string]::IsNullOrEmpty($displayName)) {
            return $ID
        } else {
            return $DisplayName
        }
    }

    function Get-UserNameFromId {
        [CmdletBinding()]
        param (
            [Parameter()]
            $ID,
            $Users
        )
        if ($id -eq 'All') {
            return 'All'
        }
        $DisplayName = $Users | Where-Object { $_.id -eq $ID } | Select-Object -ExpandProperty DisplayName
        if ([string]::IsNullOrEmpty($displayName)) {
            return $ID
        } else {
            return $DisplayName
        }
    }

    function Get-GroupNameFromId {
        param (
            [Parameter()]
            $ID,
            $Groups
        )
        if ($id -eq 'All') {
            return 'All'
        }
        $DisplayName = $Groups | Where-Object { $_.id -eq $ID } | Select-Object -ExpandProperty DisplayName
        if ([string]::IsNullOrEmpty($displayName)) {
            return 'No Data'
        } else {
            return $DisplayName
        }
    }

    function Get-ApplicationNameFromId {
        [CmdletBinding()]
        param (
            [Parameter()]
            $ID,
            $Applications,
            $ServicePrincipals
        )
        if ($id -eq 'All') {
            return 'All'
        }

        $return = $ServicePrincipals | Where-Object { $_.appId -eq $ID } | Select-Object -ExpandProperty DisplayName

        if ([string]::IsNullOrEmpty($return)) {
            $return = $Applications | Where-Object { $_.Appid -eq $ID } | Select-Object -ExpandProperty DisplayName
        }

        if ([string]::IsNullOrEmpty($return)) {
            $return = $Applications | Where-Object { $_.ID -eq $ID } | Select-Object -ExpandProperty DisplayName
        }

        if ([string]::IsNullOrEmpty($return)) {
            $return = ''
        }

        return $return
    }
    #EndRegion Helper functions

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    try {
        $GraphRequest = if ($TenantFilter -ne 'AllTenants') {
            # Single tenant functionality
            $Requests = @(
                @{
                    id     = 'policies'
                    url    = 'identity/conditionalAccess/policies'
                    method = 'GET'
                }
                @{
                    id     = 'namedLocations'
                    url    = 'identity/conditionalAccess/namedLocations'
                    method = 'GET'
                }
                @{
                    id     = 'applications'
                    url    = 'applications?$top=999&$select=appId,displayName'
                    method = 'GET'
                }
                @{
                    id     = 'roleDefinitions'
                    url    = 'roleManagement/directory/roleDefinitions?$select=id,displayName'
                    method = 'GET'
                }
                @{
                    id     = 'groups'
                    url    = 'groups?$top=999&$select=id,displayName'
                    method = 'GET'
                }
                @{
                    id     = 'users'
                    url    = 'users?$top=999&$select=id,displayName,userPrincipalName'
                    method = 'GET'
                }
                @{
                    id     = 'servicePrincipals'
                    url    = 'servicePrincipals?$top=999&$select=appId,displayName'
                    method = 'GET'
                }
            )

            $BulkResults = New-GraphBulkRequest -Requests $Requests -tenantid $TenantFilter -asapp $true

            $ConditionalAccessPolicyOutput = ($BulkResults | Where-Object { $_.id -eq 'policies' }).body.value
            $AllNamedLocations = ($BulkResults | Where-Object { $_.id -eq 'namedLocations' }).body.value
            $AllApplications = ($BulkResults | Where-Object { $_.id -eq 'applications' } ).body.value
            $AllRoleDefinitions = ($BulkResults | Where-Object { $_.id -eq 'roleDefinitions' }).body.value
            $GroupListOutput = ($BulkResults | Where-Object { $_.id -eq 'groups' }).body.value
            $UserListOutput = ($BulkResults | Where-Object { $_.id -eq 'users' }).body.value
            $AllServicePrincipals = ($BulkResults | Where-Object { $_.id -eq 'servicePrincipals' }).body.value

            foreach ($cap in $ConditionalAccessPolicyOutput) {
                [PSCustomObject]@{
                    id                                          = $cap.id
                    displayName                                 = $cap.displayName
                    customer                                    = $cap.Customer
                    Tenant                                      = $TenantFilter
                    createdDateTime                             = $(if (![string]::IsNullOrEmpty($cap.createdDateTime)) { [datetime]$cap.createdDateTime } else { '' })
                    modifiedDateTime                            = $(if (![string]::IsNullOrEmpty($cap.modifiedDateTime)) { [datetime]$cap.modifiedDateTime }else { '' })
                    state                                       = $cap.state
                    clientAppTypes                              = ($cap.conditions.clientAppTypes) -join ','
                    includePlatforms                            = ($cap.conditions.platforms.includePlatforms) -join ','
                    excludePlatforms                            = ($cap.conditions.platforms.excludePlatforms) -join ','
                    includeLocations                            = (Get-LocationNameFromId -Locations $AllNamedLocations -id $cap.conditions.locations.includeLocations) -join ','
                    excludeLocations                            = (Get-LocationNameFromId -Locations $AllNamedLocations -id $cap.conditions.locations.excludeLocations) -join ','
                    includeApplications                         = ($cap.conditions.applications.includeApplications | ForEach-Object { Get-ApplicationNameFromId -Applications $AllApplications -ServicePrincipals $AllServicePrincipals -id $_ }) -join ','
                    excludeApplications                         = ($cap.conditions.applications.excludeApplications | ForEach-Object { Get-ApplicationNameFromId -Applications $AllApplications -ServicePrincipals $AllServicePrincipals -id $_ }) -join ','
                    includeUserActions                          = ($cap.conditions.applications.includeUserActions | Out-String)
                    includeAuthenticationContextClassReferences = ($cap.conditions.applications.includeAuthenticationContextClassReferences | Out-String)
                    includeUsers                                = ($cap.conditions.users.includeUsers | ForEach-Object { Get-UserNameFromId -Users $UserListOutput -id $_ }) | Out-String
                    excludeUsers                                = ($cap.conditions.users.excludeUsers | ForEach-Object { Get-UserNameFromId -Users $UserListOutput -id $_ }) | Out-String
                    includeGroups                               = ($cap.conditions.users.includeGroups | ForEach-Object { Get-GroupNameFromId -Groups $GroupListOutput -id $_ }) | Out-String
                    excludeGroups                               = ($cap.conditions.users.excludeGroups | ForEach-Object { Get-GroupNameFromId -Groups $GroupListOutput -id $_ }) | Out-String
                    includeRoles                                = ($cap.conditions.users.includeRoles | ForEach-Object { Get-RoleNameFromId -RoleDefinitions $AllRoleDefinitions -id $_ }) | Out-String
                    excludeRoles                                = ($cap.conditions.users.excludeRoles | ForEach-Object { Get-RoleNameFromId -RoleDefinitions $AllRoleDefinitions -id $_ }) | Out-String
                    grantControlsOperator                       = ($cap.grantControls.operator) -join ','
                    builtInControls                             = ($cap.grantControls.builtInControls) -join ','
                    customAuthenticationFactors                 = ($cap.grantControls.customAuthenticationFactors) -join ','
                    termsOfUse                                  = ($cap.grantControls.termsOfUse) -join ','
                    rawjson                                     = ($cap | ConvertTo-Json -Depth 100)
                }
            }
        } else {
            # AllTenants functionality
            $Table = Get-CIPPTable -TableName cacheCAPolicies
            $PartitionKey = 'CAPolicy'
            $Filter = "PartitionKey eq '$PartitionKey'"
            $Rows = Get-CIPPAzDataTableEntity @Table -filter $Filter | Where-Object -Property Timestamp -GT (Get-Date).AddMinutes(-60)
            $QueueReference = '{0}-{1}' -f $TenantFilter, $PartitionKey
            $RunningQueue = Invoke-ListCippQueue -Reference $QueueReference | Where-Object { $_.Status -notmatch 'Completed' -and $_.Status -notmatch 'Failed' }
            # If a queue is running, we will not start a new one
            if ($RunningQueue) {
                $Metadata = [PSCustomObject]@{
                    QueueMessage = 'Still loading data for all tenants. Please check back in a few more minutes'
                    QueueId      = $RunningQueue.RowKey
                }
            } elseif (!$Rows -and !$RunningQueue) {
                # If no rows are found and no queue is running, we will start a new one
                $TenantList = Get-Tenants -IncludeErrors
                $Queue = New-CippQueueEntry -Name 'Conditional Access Policies - All Tenants' -Link '/tenant/conditional/list-policies?customerId=AllTenants' -Reference $QueueReference -TotalTasks ($TenantList | Measure-Object).Count
                $Metadata = [PSCustomObject]@{
                    QueueMessage = 'Loading data for all tenants. Please check back in a few minutes'
                    QueueId      = $Queue.RowKey
                }
                $InputObject = [PSCustomObject]@{
                    OrchestratorName = 'CAPoliciesOrchestrator'
                    QueueFunction    = @{
                        FunctionName = 'GetTenants'
                        QueueId      = $Queue.RowKey
                        TenantParams = @{
                            IncludeErrors = $true
                        }
                        DurableName  = 'ListConditionalAccessPoliciesAllTenants'
                    }
                    SkipLog          = $true
                }
                Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress) | Out-Null
            } else {
                $Metadata = [PSCustomObject]@{
                    QueueId = $RunningQueue.RowKey ?? $null
                }
                $Policies = $Rows
                # Output all policies from all tenants
                foreach ($policy in $Policies) {
                    ($policy.Policy | ConvertFrom-Json)
                }
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }

    if (!$Body) {
        $StatusCode = [HttpStatusCode]::OK
        $Body = [PSCustomObject]@{
            Results  = @($GraphRequest | Where-Object -Property id -NE $null | Sort-Object id -Descending)
            Metadata = $Metadata
        }
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
