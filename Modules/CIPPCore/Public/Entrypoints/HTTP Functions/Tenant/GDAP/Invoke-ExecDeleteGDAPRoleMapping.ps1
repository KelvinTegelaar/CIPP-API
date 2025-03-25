using namespace System.Net

Function Invoke-ExecDeleteGDAPRoleMapping {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Relationship.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $Table = Get-CIPPTable -TableName 'GDAPRoles'

    $GroupId = $Request.Query.GroupId ?? $Request.Body.GroupId
    try {
        $Filter = "PartitionKey eq 'Roles' and RowKey eq '{0}'" -f $GroupId
        $Entity = Get-CIPPAzDataTableEntity @Table -Filter $Filter
        Remove-AzDataTableEntity -Force @Table -Entity $Entity
        $Results = [pscustomobject]@{'Results' = 'Success. GDAP relationship mapping deleted' }
        Write-LogMessage -headers $Request.Headers -API $APINAME -message "GDAP relationship mapping deleted for $($GroupId)" -Sev 'Info'

    } catch {
        $Results = [pscustomobject]@{'Results' = "Failed. $($_.Exception.Message)" }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
