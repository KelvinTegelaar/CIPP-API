using namespace System.Net

Function Invoke-ListGroupTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Identity.Group.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


    Write-Host $Request.query.id

    #List new policies
    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'GroupTemplate'"
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter) | ForEach-Object {
        $data = $_.JSON | ConvertFrom-Json
        $data | Add-Member -MemberType NoteProperty -Name GUID -Value $_.RowKey -Force
        $data
    } | Sort-Object -Property displayName

    if ($Request.query.ID) { $Templates = $Templates | Where-Object -Property GUID -EQ $Request.query.id }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Templates)
        })

}
