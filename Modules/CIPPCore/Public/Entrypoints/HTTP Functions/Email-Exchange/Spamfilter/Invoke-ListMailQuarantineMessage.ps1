function Invoke-ListMailQuarantineMessage {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $Identity = $Request.Query.Identity

    try {
        $GraphRequest = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Export-QuarantineMessage' -cmdParams @{ 'Identity' = $Identity }
        $EmlBase64 = $GraphRequest.Eml
        $EmlContent = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($EmlBase64))
        $Body = @{
            'Identity' = $Identity
            'Message'  = $EmlContent
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $Body = $ErrorMessage
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })

}
