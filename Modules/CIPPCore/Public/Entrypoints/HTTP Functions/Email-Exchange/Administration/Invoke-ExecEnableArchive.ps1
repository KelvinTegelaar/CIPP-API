using namespace System.Net

function Invoke-ExecEnableArchive {
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
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $ID = $Request.Query.id ?? $Request.Body.id
    $UserName = $Request.Query.username ?? $Request.Body.username

    try {
        $ResultsArch = Set-CIPPMailboxArchive -UserID $ID -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers -ArchiveEnabled $true -Username $UserName
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ResultsArch = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return @{
        StatusCode = $StatusCode
        Body       = @{ Results = @($ResultsArch) }
    }

}
