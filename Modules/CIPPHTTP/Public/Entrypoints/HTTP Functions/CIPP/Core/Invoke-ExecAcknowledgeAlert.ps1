function Invoke-ExecAcknowledgeAlert {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Alert.ReadWrite
    .DESCRIPTION
        Acknowledges or un-acknowledges one tracked alert item in the AlertLifecycle table.
        Body: TenantFilter, RowKey (from ListAlertResults), Action (Acknowledge or
        Unacknowledge, default Acknowledge) and an optional Note. An acknowledged item stays
        on the dashboard, marked as known, until the alert stops reporting it. Only Open
        items can be acknowledged; un-acknowledging returns the item to Open.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $TenantFilter = $Request.Body.TenantFilter ?? $Request.Body.Tenant
        $RowKey = $Request.Body.RowKey
        $Action = if ([string]::IsNullOrWhiteSpace($Request.Body.Action)) { 'Acknowledge' } else { [string]$Request.Body.Action }
        $Note = [string]$Request.Body.Note
        $User = try {
            ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
        } catch { 'Unknown' }

        if ([string]::IsNullOrWhiteSpace($TenantFilter) -or [string]::IsNullOrWhiteSpace($RowKey)) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = 'TenantFilter and RowKey are required.' }
                })
        }
        if ($Action -notin @('Acknowledge', 'Unacknowledge')) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = 'Action must be Acknowledge or Unacknowledge.' }
                })
        }

        # AnyTenant: enforce tenant scope here; Get-Tenants is narrowed to the caller's allowed tenants
        $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
        if ($AllowedTenants -notcontains 'AllTenants' -and -not (Get-Tenants -TenantFilter $TenantFilter)) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Forbidden
                    Body       = @{ Results = 'Access to this tenant is not allowed' }
                })
        }

        $Table = Get-CIPPTable -tablename 'AlertLifecycle'
        $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter -Type String
        $SafeRowKey = ConvertTo-CIPPODataFilterValue -Value $RowKey -Type String
        $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeTenant' and RowKey eq '$SafeRowKey'" | Select-Object -First 1
        if (-not $Row) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body       = @{ Results = 'Alert item not found. It may have been resolved and purged.' }
                })
        }

        $Status = [string]$Row.Status
        if ($Action -eq 'Acknowledge' -and $Status -ne 'Open') {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = "Only open alerts can be acknowledged. This alert is $Status." }
                })
        }
        if ($Action -eq 'Unacknowledge' -and $Status -ne 'Acknowledged') {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = "This alert is not acknowledged. It is $Status." }
                })
        }

        $Entity = @{}
        foreach ($Prop in $Row.PSObject.Properties) {
            if ($Prop.Name -in @('ETag', 'Timestamp')) { continue }
            $Entity[$Prop.Name] = $Prop.Value
        }
        if ($Action -eq 'Acknowledge') {
            $Entity.Status = 'Acknowledged'
            $Entity.AcknowledgedBy = [string]$User
            $Entity.AcknowledgedAt = [datetime]::UtcNow.ToString('o')
            $Entity.AcknowledgeNote = $Note
        } else {
            $Entity.Status = 'Open'
            $Entity.AcknowledgedBy = ''
            $Entity.AcknowledgedAt = ''
            $Entity.AcknowledgeNote = ''
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null

        $Preview = [string]$Row.ContentPreview
        $Result = if ($Action -eq 'Acknowledge') { "Acknowledged alert: $Preview" } else { "Removed acknowledgement from alert: $Preview" }
        if ($Action -eq 'Acknowledge' -and -not [string]::IsNullOrWhiteSpace($Note)) { $Result = "$Result - Note: $Note" }
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Info' -tenant $TenantFilter

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{ Results = $Result; Status = $Entity.Status }
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to acknowledge alert: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = @{ Results = "Failed to acknowledge alert: $($ErrorMessage.NormalizedError)" }
            })
    }
}
