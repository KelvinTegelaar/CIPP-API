using namespace System.Net

function Invoke-ListConditionalAccessPolicies {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.ConditionalAccess.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


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

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    try {
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

        $GraphRequest = New-GraphBulkRequest -Requests $Requests -tenantid $TenantFilter -asapp $true

        $ConditionalAccessPolicyOutput = ($GraphRequest | Where-Object { $_.id -eq 'policies' }).body.value
        $AllNamedLocations = ($GraphRequest | Where-Object { $_.id -eq 'namedLocations' }).body.value
        $AllApplications = ($GraphRequest | Where-Object { $_.id -eq 'applications' } ).body.value
        $AllRoleDefinitions = ($GraphRequest | Where-Object { $_.id -eq 'roleDefinitions' }).body.value
        $GroupListOutput = ($GraphRequest | Where-Object { $_.id -eq 'groups' }).body.value
        $UserListOutput = ($GraphRequest | Where-Object { $_.id -eq 'users' }).body.value
        $AllServicePrincipals = ($GraphRequest | Where-Object { $_.id -eq 'servicePrincipals' }).body.value


        $GraphRequest = foreach ($cap in $ConditionalAccessPolicyOutput) {
            $temp = [PSCustomObject]@{
                id                                          = $cap.id
                displayName                                 = $cap.displayName
                customer                                    = $cap.Customer
                tenantID                                    = $TenantFilter
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
            $temp
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })

}
