Function Invoke-ExecGDAPInviteApproved {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Relationship.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    Set-CIPPGDAPInviteGroups

    $body = @{Results = @('Processing recently activated GDAP relationships') }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
