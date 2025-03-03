function Invoke-ExecEnableAutoExpandingArchive {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $ID = $Request.Body.ID
    $TenantFilter = $Request.Body.tenantFilter
    $Username = $Request.Body.username

    try {
        $Result = Set-CIPPMailboxArchive -TenantFilter $TenantFilter -UserID $ID -Username $Username -Headers $Headers -AutoExpandingArchive
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = "$Result" }
        })
}
