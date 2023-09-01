using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
$Table = Get-CIPPTable -TableName 'GDAPRoles'

Write-Host $Table
try {
      $Filter = "PartitionKey eq 'Roles' and RowKey eq '{0}'" -f $Request.Query.GroupId
      $Entity = Get-AzDataTableEntity @Table -Filter $Filter
      Remove-AzDataTableEntity @Table -Entity $Entity
      $Results = [pscustomobject]@{'Results' = 'Success. GDAP relationship mapping deleted' }
      Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "GDAP relationship mapping deleted for $($Request.Query.GroupId)" -Sev 'Info'

} catch {
      $Results = [pscustomobject]@{'Results' = "Failed. $($_.Exception.Message)" }
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
      })
