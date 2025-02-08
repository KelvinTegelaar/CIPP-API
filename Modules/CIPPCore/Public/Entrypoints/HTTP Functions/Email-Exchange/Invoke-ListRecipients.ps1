using namespace System.Net

Function Invoke-ListRecipients {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    try {
        $Select = 'id,DisplayName,ExchangeGuid,ArchiveGuid,PrimarySmtpAddress,PrimarySMTPAddress,RecipientType,RecipientTypeDetails,EmailAddresses'
        $ExoRequest = @{
            tenantid  = $TenantFilter
            cmdlet    = 'Get-Recipient'
            cmdParams = @{resultsize = 'unlimited' }
            Select    = $select
        }

        $GraphRequest = (New-ExoRequest @ExoRequest) | Select-Object id, ExchangeGuid, ArchiveGuid,
        @{ Name = 'UPN'; Expression = { $_.'PrimarySmtpAddress' } },
        @{ Name = 'mail'; Expression = { $_.'PrimarySmtpAddress' } },
        @{ Name = 'displayName'; Expression = { $_.'DisplayName' } }
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
