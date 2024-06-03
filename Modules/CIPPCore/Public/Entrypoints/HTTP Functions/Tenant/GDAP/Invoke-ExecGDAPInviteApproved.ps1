using namespace System.Net

Function Invoke-ExecGDAPInviteApproved {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Relationship.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    Set-CIPPGDAPInviteGroups

    $body = @{Results = @('Processing recently activated GDAP relationships') }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}
