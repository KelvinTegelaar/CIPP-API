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
    Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message 'Accessed this API' -Sev 'Debug'

    # Interact with the query or body of the request
    $TenantFilter = $Request.Body.tenantFilter
    $RetentionHoldState = -not $Request.Body.disable -as [bool]
    $Identity = $Request.Body.Identity
    $UserPrincipalName = $Request.Body.UPN

    # Set the parameters for the EXO request
    $ExoRequest = @{
        tenantid  = $TenantFilter
        cmdlet    = 'Set-Mailbox'
        cmdParams = @{
            Identity              = $Identity
            RetentionHoldEnabled = $RetentionHoldState
        }
    }

    # Execute the EXO request
    try {
        $null = New-ExoRequest @ExoRequest
        $Results = "Retention hold for $UserPrincipalName with Id $Identity has been set to $RetentionHoldState"
        
        Write-LogMessage -API $APIName -tenant $TenantFilter -message $Results -sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Could not set retention hold for $UserPrincipalName with Id $Identity to $RetentionHoldState. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -API $APIName -tenant $TenantFilter -message $Results -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Results }
        })
}
