Function Invoke-ExecStartManagedFolderAssistant {
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


    # Interact with query parameters or the body of the request.
    $Tenant = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $ID = $Request.Query.Id ?? $Request.Body.Id
    $UserPrincipalName = $Request.Body.UserPrincipalName
    $Identity = $ID ?? $UserPrincipalName
    $ShownName = $UserPrincipalName ?? $ID


    $ExoParams = @{
        Identity          = $Identity
        FullCrawl         = $true
    }

    try {
        $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Start-ManagedFolderAssistant' -cmdParams $ExoParams
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

    $Body = [pscustomobject] @{ 'Results' = $Result }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
