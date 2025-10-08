function Invoke-ListMailboxRestores {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    try {
        if ([bool]$Request.Query.Statistics -eq $true -and $Request.Query.Identity) {
            $ExoRequest = @{
                tenantid  = $TenantFilter
                cmdlet    = 'Get-MailboxRestoreRequestStatistics'
                cmdParams = @{ Identity = $Request.Query.Identity }
            }

            if ([bool]$Request.Query.IncludeReport -eq $true) {
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
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })
}
