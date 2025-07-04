function Invoke-ListMailboxRestores {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $Identity = $Request.Query.Identity
    $IncludeReport = [bool]$Request.Query.IncludeReport
    $Statistics = [bool]$Request.Query.Statistics

    try {
        if ($Statistics -eq $true -and $Identity) {
            $ExoRequest = @{
                tenantid  = $TenantFilter
                cmdlet    = 'Get-MailboxRestoreRequestStatistics'
                cmdParams = @{ Identity = $Identity }
            }

            if ($IncludeReport -eq $true) {
                $ExoRequest.cmdParams.IncludeReport = $true
            }
            $GraphRequest = New-ExoRequest @ExoRequest

        } else {
            $ExoRequest = @{
                tenantid = $TenantFilter
                cmdlet   = 'Get-MailboxRestoreRequest'
            }

            $RestoreRequests = (New-ExoRequest @ExoRequest)
            $GraphRequest = $RestoreRequests
        }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
        $GraphRequest = $ErrorMessage
    }
    return @{
        StatusCode = $StatusCode
        Body       = @($GraphRequest)
    }
}
