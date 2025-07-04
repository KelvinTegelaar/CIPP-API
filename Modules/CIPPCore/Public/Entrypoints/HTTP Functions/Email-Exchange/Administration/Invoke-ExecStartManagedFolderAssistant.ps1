using namespace System.Net

function Invoke-ExecStartManagedFolderAssistant {
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
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $Tenant = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $ID = $Request.Query.Id ?? $Request.Body.Id
    $UserPrincipalName = $Request.Body.UserPrincipalName
    $Identity = $ID ?? $UserPrincipalName
    $ShownName = $UserPrincipalName ?? $ID

    try {
        $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Start-ManagedFolderAssistant' -cmdParams @{Identity = $Identity; FullCrawl = $true }
        $Result = "Successfully started Managed Folder Assistant for mailbox $($ShownName)."
        $Severity = 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to start Managed Folder Assistant for mailbox $($ShownName). Error: $($ErrorMessage.NormalizedError)"
        $Severity = 'Error'
        $StatusCode = [HttpStatusCode]::InternalServerError
    } finally {
        Write-LogMessage -Headers $Headers -API $APIName -tenant $Tenant -message $Result -Sev $Severity -LogData $ErrorMessage
    }

    return @{
        StatusCode = $StatusCode
        Body       = @{ Results = @($Result) }
    }
}
