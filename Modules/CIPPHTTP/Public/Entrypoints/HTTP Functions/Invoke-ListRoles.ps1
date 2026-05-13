function Invoke-ListRoles {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Role.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter

    try {
        [System.Collections.Generic.List[PSCustomObject]]$Roles = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/directoryRoles' -tenantid $TenantFilter

        $MemberRequests = $Roles | ForEach-Object {
            @{
                id     = $_.id
                method = 'GET'
                url    = "/directoryRoles/$($_.id)/members"
            }
        }
        $MemberResponses = New-GraphBulkRequest -Requests $MemberRequests -tenantid $TenantFilter -Version 'v1.0'

        $MemberMap = @{}
        foreach ($Response in $MemberResponses) {
            $MemberMap[$Response.id] = $Response.body.value
        }

        $GraphRequest = foreach ($Role in $Roles) {
            $Members = if ($MemberMap[$Role.id]) {
                $MemberMap[$Role.id] | ForEach-Object { [PSCustomObject]@{
                        displayName       = $_.displayName
                        userPrincipalName = $_.userPrincipalName
                        id                = $_.id
                    } }
            }
            [PSCustomObject]@{
                Id             = $Role.id
                roleTemplateId = $Role.roleTemplateId
                DisplayName    = $Role.displayName
                Description    = $Role.description
                Members        = @($Members)
                SID            = (Convert-AzureAdObjectIdToSid -ObjectID $Role.id)
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        "Failed to list roles for tenant $TenantFilter. $($ErrorMessage.NormalizedError)"
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $GraphRequest
    }
}
