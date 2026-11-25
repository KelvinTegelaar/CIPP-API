function Invoke-ListDefenderMachineActions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.Defender.Read
    .SYNOPSIS
        Defender isolation and antivirus scan history for one device
    .DESCRIPTION
        Reads up to 50 isolate, release and antivirus scan actions for one Microsoft Defender for Endpoint device live from Defender, newest first: type, status, scope, requestor, requestor comment, when the action was created and last updated, and Defender's error code. Returns an empty array when the device has none.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    # One tenant: its default domain or tenant id.
    $TenantFilter = $Request.Query.tenantFilter
    # The device's Defender id (40 hexadecimal characters), as listed by ListDefenderMachines.
    $MachineId = $Request.Query.machineId

    if ($TenantFilter -isnot [string] -or [string]::IsNullOrWhiteSpace($TenantFilter) -or $TenantFilter -eq 'AllTenants' -or $TenantFilter -like 'group:*') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'tenantFilter must name one tenant.' } })
    }
    if ($MachineId -isnot [string] -or $MachineId -notmatch '\A[0-9a-fA-F]{40}\z') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'machineId must be a Defender device id (40 hexadecimal characters).' } })
    }

    try {
        $Filter = [uri]::EscapeDataString("machineId eq '$MachineId' and (type eq 'Isolate' or type eq 'Unisolate' or type eq 'RunAntiVirusScan')")
        $DefenderActions = New-GraphGetRequest -uri "https://api.securitycenter.microsoft.com/api/machineactions?`$filter=$Filter&`$top=50" -tenantid $TenantFilter -scope 'https://api.securitycenter.microsoft.com/.default' -AsApp $true -noPagination $true
        $Body = @(foreach ($Item in @($DefenderActions | Sort-Object -Property creationDateTimeUtc -Descending)) {
                [PSCustomObject]@{
                    id                    = $Item.id
                    type                  = $Item.type
                    status                = $Item.status
                    scope                 = $Item.scope
                    requestor             = $Item.requestor
                    requestorComment      = $Item.requestorComment
                    creationDateTimeUtc   = $Item.creationDateTimeUtc
                    lastUpdateDateTimeUtc = $Item.lastUpdateDateTimeUtc
                    errorHResult          = $Item.errorHResult
                }
            })
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to read the Defender action history for device $($MachineId): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -sev Error -LogData $ErrorMessage
        $Body = @{ Results = $Message }
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
