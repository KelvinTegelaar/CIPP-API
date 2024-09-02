function Invoke-ListMailQuarantineMessage {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $Tenantfilter = $Request.Query.Tenantfilter

    try {
        $GraphRequest = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Export-QuarantineMessage' -cmdParams @{ 'Identity' = $Request.Query.Identity }
        $EmlBase64 = $GraphRequest.Eml
        $EmlContent = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($EmlBase64))
        $Body = @{
            'Identity' = $Request.Query.Identity
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
