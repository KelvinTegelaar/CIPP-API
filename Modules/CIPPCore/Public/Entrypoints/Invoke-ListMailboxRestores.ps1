function Invoke-ListMailboxRestores {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

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
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })
}
