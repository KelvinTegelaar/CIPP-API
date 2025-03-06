using namespace System.Net

Function Invoke-ListGDAPInvite {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Relationship.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Interact with query parameters or the body of the request.
    $RelationshipId = $Request.Query.RelationshipId

    $Table = Get-CIPPTable -TableName 'GDAPInvites'
    if (![string]::IsNullOrEmpty($RelationshipId)) {
        $Invite = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$($RelationshipId)'"
    } else {
        $Invite = Get-CIPPAzDataTableEntity @Table | ForEach-Object {
            $_.RoleMappings = @(try { $_.RoleMappings | ConvertFrom-Json } catch { $_.RoleMappings })
            $_
        }
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Invite)
        })
}
