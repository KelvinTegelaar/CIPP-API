function Invoke-ListMailboxForwarding {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.tenantFilter
    $ForwardingOnly = $Request.Query.ForwardingOnly

    try {
        # Call the report function with proper parameters
        $ReportParams = @{
            TenantFilter = $TenantFilter
        }
        if ($ForwardingOnly -eq 'true') {
            $ReportParams.ForwardingOnly = $true
        }

        try {
            $GraphRequest = Get-CIPPMailboxForwardingReport @ReportParams
            $StatusCode = [HttpStatusCode]::OK
        } catch {
            $StatusCode = [HttpStatusCode]::InternalServerError
            $GraphRequest = $_.Exception.Message
        }

        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Mailbox forwarding report listed for $($TenantFilter)" -sev Debug

        return ([HttpResponseContext]@{
                StatusCode = $StatusCode
                Body       = @($GraphRequest)
            })

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
