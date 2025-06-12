function Set-CIPPDeviceState {
    <#
    .SYNOPSIS
    Sets or modifies the state of a device in Microsoft Graph.

    .DESCRIPTION
    This function allows you to enable, disable, or delete a device by making
    corresponding requests to the Microsoft Graph API. It logs the result
    and returns a success or error message based on the outcome.

    .PARAMETER Action
    Specifies the action to perform on the device. Valid actions are:
        - Enable: Enable the device
        - Disable: Disable the device
        - Delete: Remove the device from the tenant

    .PARAMETER DeviceID
    Specifies the unique identifier (Object ID) of the device to be managed.

    .PARAMETER TenantFilter
    Specifies the tenant ID or domain against which to perform the operation.

    .PARAMETER Headers
    Specifies the user who initiated the request for logging purposes.

    .PARAMETER APIName
    Specifies the name of the API call for logging purposes. Defaults to 'Set Device State'.

    .EXAMPLE
    Set-CIPPDeviceState -Action Enable -DeviceID "1234abcd-5678-efgh-ijkl-9012mnopqrst" -TenantFilter "contoso.onmicrosoft.com" -Headers "admin@contoso.onmicrosoft.com"

    This command enables the specified device within the given tenant.

    .EXAMPLE
    Set-CIPPDeviceState -Action Delete -DeviceID "1234abcd-5678-efgh-ijkl-9012mnopqrst" -TenantFilter "contoso.onmicrosoft.com"

    This command removes the specified device from the tenant.
#>
    param (
        [Parameter(Mandatory = $true)][ValidateSet('Enable', 'Disable', 'Delete')]$Action,

        [ValidateScript({
                if ([Guid]::TryParse($_, [ref] [Guid]::Empty)) {
                    $true
                } else {
                    throw 'DeviceID must be a valid GUID.'
                }
            })]
        [Parameter(Mandatory = $true)]$DeviceID,

        [Parameter(Mandatory = $true)]$TenantFilter,
        $Headers,
        $APIName = 'Set Device State'
    )
    $Url = "https://graph.microsoft.com/beta/devices/$($DeviceID)"

    try {
        switch ($Action) {
            'Delete' {
                $ActionResult = New-GraphPOSTRequest -uri $Url -type DELETE -tenantid $TenantFilter
            }
            'Disable' {
                $ActionResult = New-GraphPOSTRequest -uri $Url -type PATCH -tenantid $TenantFilter -body '{"accountEnabled": false }'
            }
            'Enable' {
                $ActionResult = New-GraphPOSTRequest -uri $Url -type PATCH -tenantid $TenantFilter -body '{"accountEnabled": true }'
            }
        }
        Write-Host $ActionResult
        Write-LogMessage -headers $Headers -API $APIName -message "Executed action $($Action) on $($DeviceID)" -Sev Info
        return "Executed action $($Action) on $($DeviceID)"
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to queue action $($Action) on $($DeviceID). Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        throw "Failed to queue action $($Action) on $($DeviceID). Error: $($ErrorMessage.NormalizedError)"
    }


}
