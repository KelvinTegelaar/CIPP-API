function Invoke-ExecSetLitigationHold {
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
    $LitHoldState = -not $Request.Body.disable -as [bool]
    $Identity = $Request.Body.Identity
    $UserPrincipalName = $Request.Body.UPN
    $Days = $Request.Body.days -as [int]

    # Set the parameters for the EXO request
    $ExoRequest = @{
        tenantid  = $TenantFilter
        cmdlet    = 'Set-Mailbox'
        cmdParams = @{
            Identity              = $Identity
            LitigationHoldEnabled = $LitHoldState
        }
    }

    # Add the duration of the hold if specified
    if ($Days -ne 0 -and $LitHoldState -eq $true) {
        $ExoRequest.cmdParams['LitigationHoldDuration'] = $Days
    }

    # Execute the EXO request
    try {
        $null = New-ExoRequest @ExoRequest
        $Results = "Litigation hold for $UserPrincipalName with Id $Identity has been set to $LitHoldState"
        if ($Days -ne 0 -and $LitHoldState -eq $true) {
            $Results += " for $Days days"
        }
        Write-LogMessage -API $APIName -tenant $TenantFilter -message $Results -sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Could not set litigation hold for $UserPrincipalName with Id $Identity to $LitHoldState. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -API $APIName -tenant $TenantFilter -message $Results -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Results }
        })
}
