function Invoke-ExecRemoveTenant {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Administration.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    if ($Request.Body.TenantID -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
        $Body = @{Results = "Tenant ID $($Request.Body.TenantID) is not a valid GUID." }
        $StatusCode = [HttpStatusCode]::BadRequest
    } else {
        $Table = Get-CippTable -tablename 'Tenants'
        $Tenant = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Tenants' and RowKey eq '$($Request.Body.TenantID)'" -Property RowKey, PartitionKey, customerId, displayName
        if ($Tenant) {
            try {
                Remove-AzDataTableEntity @Table -Entity $Tenant
                $Body = @{Results = "$($Tenant.displayName) ($($Tenant.customerId)) deleted from CIPP. Note: This does not remove the GDAP relationship, see the Tenant Offboarding wizard to perform that action." }
                $StatusCode = [HttpStatusCode]::OK
            } catch {
                $Body = @{Results = "Failed to delete $($Tenant.displayName) ($($Tenant.customerId)) from CIPP. Error: $($_.Exception.Message)" }
                $StatusCode = [HttpStatusCode]::InternalServerError
            }
        } else {
            $Body = @{Results = "Tenant $($Request.Body.TenantID) not found in CIPP." }
            $StatusCode = [HttpStatusCode]::NotFound
        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
