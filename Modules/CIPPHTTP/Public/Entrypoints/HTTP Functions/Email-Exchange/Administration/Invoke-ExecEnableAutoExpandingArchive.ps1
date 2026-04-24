function Invoke-ExecEnableAutoExpandingArchive {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Headers = $Request.Headers


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

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = "$Result" }
        })
}
