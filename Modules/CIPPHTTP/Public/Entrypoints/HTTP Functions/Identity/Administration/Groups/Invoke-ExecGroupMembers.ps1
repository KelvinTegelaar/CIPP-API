function Invoke-ExecGroupMembers {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Group.ReadWrite
    .DESCRIPTION
        Manages group membership (members and owners) via a switch-style action parameter.
        Accepts one or more directory object IDs, UPNs, or mail addresses (users, groups, etc.).
        Automatically resolves the group type from Graph to route through the correct API (Graph or Exchange).

        Supported actions: addMember, removeMember, addOwner, removeOwner
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $Body = $Request.Body

    $Action = $Body.action
    $GroupId = $Body.groupId
    $TenantFilter = $Body.tenantFilter
    # Accept a single string or an array of strings (IDs, UPNs, or mail)
    $Users = @($Body.users | Where-Object { $_ })

    if (-not $Action -or -not $GroupId -or -not $TenantFilter -or $Users.Count -eq 0) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Required parameters: action, groupId, tenantFilter, users (one or more directory object IDs/UPNs/mail addresses)' }
            })
    }

    $ValidActions = @('addMember', 'removeMember', 'addOwner', 'removeOwner')
    if ($Action -notin $ValidActions) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = "Invalid action '$Action'. Valid actions: $($ValidActions -join ', ')" }
            })
    }

    try {
        switch ($Action) {
            'addMember' {
                $Result = Add-CIPPGroupMember -Headers $Headers -GroupId $GroupId -Member $Users -TenantFilter $TenantFilter -APIName $APIName
            }
            'removeMember' {
                $Result = Remove-CIPPGroupMember -Headers $Headers -GroupId $GroupId -Member $Users -TenantFilter $TenantFilter -APIName $APIName
            }
            'addOwner' {
                $Result = Add-CIPPGroupOwner -Headers $Headers -GroupId $GroupId -Owner $Users -TenantFilter $TenantFilter -APIName $APIName
            }
            'removeOwner' {
                $Result = Remove-CIPPGroupOwner -Headers $Headers -GroupId $GroupId -Owner $Users -TenantFilter $TenantFilter -APIName $APIName
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
