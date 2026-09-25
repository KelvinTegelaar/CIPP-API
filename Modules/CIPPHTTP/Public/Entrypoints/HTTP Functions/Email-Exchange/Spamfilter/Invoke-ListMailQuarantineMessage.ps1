function Invoke-ListMailQuarantineMessage {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.Read
    .DESCRIPTION
        Exports and retrieves the raw EML content of a specific quarantined email message by its Identity.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $Identity = $Request.Query.Identity

    try {
        $GraphRequest = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Export-QuarantineMessage' -cmdParams @{ 'Identity' = $Identity }
        # This is one of the few places CIPP hands message content to an operator; record who pulled what.
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -tenant $TenantFilter -message "Exported the raw EML of quarantined message $Identity" -Sev 'Info'
        $EmlBase64 = $GraphRequest.Eml
        $EmlContent = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($EmlBase64))
        $Body = @{
            'Identity'  = $Identity
            'Message'   = $EmlContent
            'EmlBase64' = $EmlBase64
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $Body = $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })

}
