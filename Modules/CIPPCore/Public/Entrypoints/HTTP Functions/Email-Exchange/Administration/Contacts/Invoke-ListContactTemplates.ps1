function Invoke-ListContactTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Exchange.Contact.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    $Table = Get-CippTable -tablename 'templates'
    $Templates = Get-ChildItem 'Config\*.ContactTemplate.json' | ForEach-Object {
        $Entity = @{
            JSON         = "$(Get-Content $_)"
            RowKey       = "$($_.name)"
            PartitionKey = 'ContactTemplate'
            GUID         = "$($_.name)"
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
    }

    # Check if a specific template ID is requested
    if ($Request.query.ID -or $Request.query.id) {
        $RequestedID = $Request.query.ID ?? $Request.query.id
        Write-LogMessage -headers $Headers -API $APIName -message "Retrieving specific template with ID: $RequestedID" -Sev 'Debug'

        # Query directly for the specific template by RowKey for efficiency
        $Filter = "PartitionKey eq 'ContactTemplate' and RowKey eq '$RequestedID'"
        $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter) | ForEach-Object {
            $GUID = $_.RowKey
            $data = $_.JSON | ConvertFrom-Json
            $data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $GUID
            $data
        }

        if (-not $Templates) {
            Write-LogMessage -headers $Headers -API $APIName -message "Template with ID $RequestedID not found" -sev 'Warn'
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body       = @{ Error = "Template with ID $RequestedID not found" }
                })
            return
        }
    } else {
        # List all policies if no specific ID requested
        Write-LogMessage -headers $Headers -API $APIName -message 'Retrieving all contact templates' -Sev 'Debug'

        $Filter = "PartitionKey eq 'ContactTemplate'"
        $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter) | ForEach-Object {
            $GUID = $_.RowKey
            $data = $_.JSON | ConvertFrom-Json
            $data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $GUID
            $data
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Templates)
        })
}
