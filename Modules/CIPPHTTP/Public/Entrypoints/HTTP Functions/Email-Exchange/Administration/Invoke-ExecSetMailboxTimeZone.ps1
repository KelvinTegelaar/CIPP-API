function Invoke-ExecSetMailboxTimeZone {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    .SYNOPSIS
        Set the time zone of a mailbox
    .DESCRIPTION
        Sets the mailbox time zone and the working hours time zone to the selected Windows time zone ID, for example British Columbia Standard Time. Existing calendar items are not moved; use ExecCalendarTimeZoneMigration for that.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    # Mailbox ExchangeGuid
    $Identity = $Request.Body.Identity
    $Mailbox = $Request.Body.UPN ?? $Identity
    # Windows time zone ID to set, e.g. British Columbia Standard Time
    $TimeZone = $Request.Body.TimeZone.value ?? $Request.Body.TimeZone

    if (-not $Identity -or [string]::IsNullOrWhiteSpace($TimeZone)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Identity and TimeZone are required' } })
    }

    try {
        $Result = Set-CIPPMailboxTimeZone -UserID $Identity -Username $Mailbox -TimeZone $TimeZone -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
