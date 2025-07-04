function Invoke-ExecSetRetentionHold {
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

    # Interact with the query or body of the request
    $TenantFilter = $Request.Body.tenantFilter
    $RetentionHoldState = -not $Request.Body.disable -as [bool]
    $Identity = $Request.Body.Identity
    $UserPrincipalName = $Request.Body.UPN

    # Execute the EXO request
    try {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-Mailbox' -cmdParams @{Identity = $Identity; RetentionHoldEnabled = $RetentionHoldState }
        $Results = "Retention hold for $UserPrincipalName with Id $Identity has been set to $RetentionHoldState"

        Write-LogMessage -API $APIName -tenant $TenantFilter -message $Results -headers $Headers -sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Could not set retention hold for $UserPrincipalName with Id $Identity to $RetentionHoldState. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -API $APIName -tenant $TenantFilter -message $Results -headers $Headers -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return @{
        StatusCode = $StatusCode
        Body       = @{ Results = @($Results) }
    }
}
