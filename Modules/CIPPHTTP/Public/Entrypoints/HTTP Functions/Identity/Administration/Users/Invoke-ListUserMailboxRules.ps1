Function Invoke-ListUserMailboxRules {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $UserID = $Request.Query.UserID
    try {
        $UserEmail = if ([string]::IsNullOrWhiteSpace($Request.Query.userEmail)) { $UserID } else { $Request.Query.userEmail }
        $Result = New-ExoRequest -Anchor $UserID -tenantid $TenantFilter -cmdlet 'Get-InboxRule' -cmdParams @{mailbox = $UserID; IncludeHidden = $true } |
            Where-Object { $_.Name -ne 'Junk E-Mail Rule' -and $_.Name -notlike 'Microsoft.Exchange.OOF.*' } | Select-Object * -ExcludeProperty RuleIdentity
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to retrieve mailbox rules for $UserEmail : Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -tenant $TenantFilter -API $APIName -message $Result -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Result)
        })

}
