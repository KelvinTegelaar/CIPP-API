function Invoke-ExecSetDeviceExtensionAttribute {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Device.ReadWrite
    .DESCRIPTION
        Sets or clears one extension attribute (1 to 15) on an Entra device.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    # Entra device object id.
    $DeviceId = $Request.Body.ID
    # Extension attribute number, 1 to 15.
    $Attribute = $Request.Body.Attribute.value ?? $Request.Body.Attribute
    # New value. Empty clears the attribute.
    $Value = $Request.Body.Value

    if (-not $DeviceId) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'ID is required' } })
    }
    $Number = $Attribute -as [int]
    if ($Number -lt 1 -or $Number -gt 15 -or "$Attribute" -notmatch '^\d+$') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Attribute must be a number from 1 to 15' } })
    }
    $Name = "extensionAttribute$Number"
    $NewValue = if ([string]::IsNullOrWhiteSpace($Value)) { $null } else { "$Value".Trim() }

    try {
        $Body = ConvertTo-Json -InputObject @{ extensionAttributes = @{ $Name = $NewValue } } -Compress
        $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/devices/$DeviceId" -tenantid $TenantFilter -type PATCH -body $Body
        $Result = if ($null -eq $NewValue) { "Cleared extension attribute $Number" } else { "Set extension attribute $Number to '$NewValue'" }
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "$Result on device $DeviceId" -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to update extension attribute $Number. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "$Result Device $DeviceId" -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
