function Invoke-ListUsersAndGroups {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.Read
    .DESCRIPTION
        Lists both users and groups for a tenant in a single batch call, returning ID and display name for selection/lookup purposes.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.TenantFilter
    $select = 'id,displayName,userPrincipalName'

    try {
        # Build batch requests for users and groups
        $BulkRequests = @(
            @{
                id     = 'users'
                method = 'GET'
                url    = "users?`$select=$select&`$top=999&"
            }
            @{
                id     = 'groups'
                method = 'GET'
                url    = "groups?`$select=id,displayName,groupTypes,mailEnabled,securityEnabled&`$top=999"
            }
        )
        $BulkResults = New-GraphBulkRequest -Requests $BulkRequests -tenantid $TenantFilter
        $Users = ($BulkResults | Where-Object { $_.id -eq 'users' }).body.value | Select-Object *, @{Name = '@odata.type'; Expression = { '#microsoft.graph.user' } }
        $Groups = ($BulkResults | Where-Object { $_.id -eq 'groups' }).body.value | Where-Object { $_.groupTypes -notcontains 'Unified' } | Select-Object id, displayName, mailEnabled, securityEnabled, @{Name = 'userPrincipalName'; Expression = { $null } }, @{Name = '@odata.type'; Expression = { '#microsoft.graph.group' } }
        $GraphRequest = @($Users) + @($Groups) | Sort-Object displayName
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }
    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @{ Results = @($GraphRequest) }
    }
}
