function Invoke-ListJITAdminTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Identity.Role.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    # Get the TenantFilter from query parameters
    $TenantFilter = $Request.Query.TenantFilter

    # Get the includeAllTenants flag from query or body parameters (defaults to true)
    $IncludeAllTenants = if ($Request.Query.includeAllTenants -eq 'false' -or $Request.Body.includeAllTenants -eq 'false') {
        $false
    } else {
        $true
    }

    # Get the templates table
    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'JITAdminTemplate'"

    # Retrieve all JIT Admin templates
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter) | ForEach-Object {
        try {
            $row = $_
            $data = $row.JSON | ConvertFrom-Json -Depth 100 -ErrorAction Stop
            $data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $row.GUID -Force
            $data | Add-Member -NotePropertyName 'RowKey' -NotePropertyValue $row.RowKey -Force
            $data
        } catch {
            Write-LogMessage -headers $Headers -API $APIName -message "Failed to process JIT Admin template: $($row.RowKey) - $($_.Exception.Message)" -sev 'Warn'
        }
    }

    # Filter by tenant if TenantFilter is provided
    if ($TenantFilter) {
        if ($TenantFilter -eq 'AllTenants') {
            # When requesting AllTenants, return only templates stored under AllTenants
            $Templates = $Templates | Where-Object -Property tenantFilter -EQ 'AllTenants'
        } else {
            # When requesting a specific tenant
            if ($IncludeAllTenants) {
                # Include both tenant-specific and AllTenants templates
                $Templates = $Templates | Where-Object { $_.tenantFilter -eq $TenantFilter -or $_.tenantFilter -eq 'AllTenants' }
            } else {
                # Return only tenant-specific templates (exclude AllTenants)
                $Templates = $Templates | Where-Object -Property tenantFilter -EQ $TenantFilter
            }
        }
    }

    # Sort by template name
    $Templates = $Templates | Sort-Object -Property templateName

    # If a specific GUID is requested, filter to that template
    if ($Request.query.GUID) {
        $Templates = $Templates | Where-Object -Property GUID -EQ $Request.query.GUID
    }

    $Templates = ConvertTo-Json -InputObject @($Templates) -Depth 100

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Templates
        })
}
