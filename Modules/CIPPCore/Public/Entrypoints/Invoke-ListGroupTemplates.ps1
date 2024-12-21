using namespace System.Net

Function Invoke-ListGroupTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Group.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'
    Write-Host $Request.query.id

    #List new policies
    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'GroupTemplate'"
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter) | ForEach-Object {
        $data = $_.JSON | ConvertFrom-Json
        $data | Add-Member -MemberType NoteProperty -Name GUID -Value $_.RowKey -Force
        #Output casing of Displayname does not match front-ends expectations. Lazy fix for now, I think this may be related to templates table layout.
        $data | Add-Member -MemberType NoteProperty -Name displayName -Value $data.Displayname -Force
        $data.PSObject.Properties.Remove('Displayname')
        $data
    } | Sort-Object -Property displayName

    if ($Request.query.ID) { $Templates = $Templates | Where-Object -Property GUID -EQ $Request.query.id }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Templates)
        })

}
