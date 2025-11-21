function Invoke-ListNewUserDefaults {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Identity.User.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    Write-Host 'Listing New User Default Templates'

    # Get the TenantFilter from query parameters
    $TenantFilter = $Request.Query.TenantFilter
    Write-Host "TenantFilter from request: $TenantFilter"

    # Get the templates table
    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'UserDefaultTemplate'"

    # Retrieve all User Default templates
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter) | ForEach-Object {
        try {
            $row = $_
            $data = $row.JSON | ConvertFrom-Json -Depth 100 -ErrorAction Stop
            $data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $row.GUID -Force
            $data | Add-Member -NotePropertyName 'RowKey' -NotePropertyValue $row.RowKey -Force
            Write-Host "Template found: $($data.templateName), tenantFilter: $($data.tenantFilter)"
            $data
        } catch {
            Write-Warning "Failed to process User Default template: $($row.RowKey) - $($_.Exception.Message)"
        }
    }

    Write-Host "Total templates before filtering: $($Templates.Count)"

    # Filter by tenant if TenantFilter is provided
    if ($TenantFilter) {
        $Templates = $Templates | Where-Object -Property tenantFilter -EQ $TenantFilter
        Write-Host "Templates after filtering: $($Templates.Count)"
    }

    # Sort by template name
    $Templates = $Templates | Sort-Object -Property templateName

    # If a specific ID is requested, filter to that template
    if ($Request.query.ID) {
        $Templates = $Templates | Where-Object -Property GUID -EQ $Request.query.ID
    }

    $Templates = ConvertTo-Json -InputObject @($Templates) -Depth 100

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Templates
        })
}
