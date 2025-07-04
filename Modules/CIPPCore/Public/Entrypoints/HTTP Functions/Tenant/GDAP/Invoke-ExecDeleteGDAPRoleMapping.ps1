using namespace System.Net

function Invoke-ExecDeleteGDAPRoleMapping {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Relationship.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


    $Table = Get-CIPPTable -TableName 'GDAPRoles'
    $GroupId = $Request.Query.GroupId ?? $Request.Body.GroupId
    try {
        $Filter = "PartitionKey eq 'Roles' and RowKey eq '{0}'" -f $GroupId
        $Entity = Get-CIPPAzDataTableEntity @Table -Filter $Filter
        Remove-AzDataTableEntity -Force @Table -Entity $Entity
        $Results = 'Success. GDAP relationship mapping deleted'
        Write-LogMessage -headers $Headers -API $APIName -message $Results -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to delete GDAP relationship mapping. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Results -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return @{
        StatusCode = $StatusCode
        Body       = @{ Results = $Results }
    }
}
