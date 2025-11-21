function Invoke-ListAssignmentFilterTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.MEM.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $ID = $Request.Query.ID

    #List assignment filter templates
    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'AssignmentFilterTemplate'"
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter) | ForEach-Object {
        $data = $_.JSON | ConvertFrom-Json

        [PSCustomObject]@{
            displayName                    = $data.displayName
            description                    = $data.description
            platform                       = $data.platform
            rule                           = $data.rule
            assignmentFilterManagementType = $data.assignmentFilterManagementType
            GUID                           = $_.RowKey
        }
    } | Sort-Object -Property displayName

    if ($ID) { $Templates = $Templates | Where-Object -Property GUID -EQ $ID }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Templates)
        })

}
