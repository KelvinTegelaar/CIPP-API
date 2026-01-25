function Invoke-ListUsersAndGroups {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.Read
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
                url    = "groups?`$select=id,displayName&`$top=999"
            }
        )
        $BulkResults = New-GraphBulkRequest -Requests $BulkRequests -tenantid $TenantFilter
        $Users = ($BulkResults | Where-Object { $_.id -eq 'users' }).body.value | Select-Object *, @{Name = '@odata.type'; Expression = { '#microsoft.graph.user' } }
        $Groups = ($BulkResults | Where-Object { $_.id -eq 'groups' }).body.value | Select-Object id, displayName, @{Name = 'userPrincipalName'; Expression = { $null } }, @{Name = '@odata.type'; Expression = { '#microsoft.graph.group' } }
        $GraphRequest = @($Users) + @($Groups) | Sort-Object displayName
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }
    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @($GraphRequest)
    }
}
