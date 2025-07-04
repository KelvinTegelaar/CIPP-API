using namespace System.Net

function Invoke-ListGDAPInvite {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Relationship.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


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
    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($Invite)
    }
}
