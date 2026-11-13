function Invoke-ListEnterpriseAppExchangeRbac {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.Read
    .DESCRIPTION
        Lists the Exchange access of an enterprise application (service principal): whether it is registered in
        Exchange, its RBAC for Applications role assignments with their scope, and the application access policies
        that apply to it (its own and those for every app). Also returns the Application roles and management scopes
        of the tenant, to pick from when assigning.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $ServicePrincipalId = "$($Request.Query.ServicePrincipalId ?? $Request.Body.ServicePrincipalId)"

    if (-not $TenantFilter -or $ServicePrincipalId -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'tenantFilter and a valid ServicePrincipalId are required' }
            })
    }

    try {
        $Sp = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals/$ServicePrincipalId`?`$select=id,appId,displayName" -tenantid $TenantFilter
        $ExoServicePrincipals = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-ServicePrincipal')
        $ExoSp = $ExoServicePrincipals | Where-Object { [string]$_.ObjectId -eq $ServicePrincipalId -or [string]$_.AppId -eq $Sp.appId } | Select-Object -First 1
        $ManagementScopes = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-ManagementScope')

        $Assignments = @(Get-CIPPExoAppRoleAssignment -TenantFilter $TenantFilter -ServicePrincipals $ExoServicePrincipals -ManagementScopes $ManagementScopes |
                Where-Object { $_.servicePrincipalId -eq $ServicePrincipalId -or ($_.appId -and $_.appId -eq $Sp.appId) } |
                Sort-Object role)

        $AccessPolicies = @(Get-CIPPExoApplicationAccessPolicy -TenantFilter $TenantFilter |
                Where-Object { $_.appId -eq $Sp.appId -or $_.appId -eq '*' } |
                ForEach-Object {
                    $_ | Add-Member -NotePropertyName appliesToEveryApp -NotePropertyValue ($_.appId -eq '*') -PassThru
                })

        $AvailableRoles = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-ManagementRole' |
                Where-Object { [string]$_.Name -like 'Application *' } |
                Sort-Object Name |
                ForEach-Object { [PSCustomObject]@{ name = [string]$_.Name; description = [string]$_.Description } })

        $Scopes = @($ManagementScopes | Where-Object { $_.Name } | Sort-Object Name | ForEach-Object {
                [PSCustomObject]@{
                    name            = [string]$_.Name
                    recipientFilter = [string]$_.RecipientFilter
                    # Exclusive scopes do not restrict an app's access.
                    exclusive       = [bool]$_.Exclusive
                }
            })

        $Body = @{
            Results = [PSCustomObject]@{
                displayName      = $Sp.displayName
                appId            = $Sp.appId
                registered       = [bool]$ExoSp
                exchangeIdentity = if ($ExoSp) { [string]($ExoSp.Identity ?? $ExoSp.Name) } else { $null }
                assignments      = $Assignments
                accessPolicies   = $AccessPolicies
                availableRoles   = $AvailableRoles
                managementScopes = $Scopes
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to read the Exchange access of $($ServicePrincipalId): $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Body = @{ Results = "Failed to read the Exchange access of this application: $($ErrorMessage.NormalizedError)" }
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
