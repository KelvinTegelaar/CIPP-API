function Invoke-ExecSetCASMailbox {
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

    $TenantFilter = $Request.Body.tenantFilter
    $Identity = $Request.Body.Identity
    $DisplayName = $Request.Body.DisplayName ?? $Identity

    # The CAS protocols we allow toggling. Note SmtpClientAuthenticationDisabled is inverted:
    # $true means SMTP client authentication is DISABLED for the mailbox.
    $ValidProtocols = @(
        'OWAEnabled'
        'ECPEnabled'
        'IMAPEnabled'
        'POPEnabled'
        'MAPIEnabled'
        'EWSEnabled'
        'ActiveSyncEnabled'
        'SmtpClientAuthenticationDisabled'
    )

    # Build the cmdlet parameters from any valid protocol values supplied in the body.
    $CmdParams = @{ Identity = $Identity }
    foreach ($Protocol in $ValidProtocols) {
        if ($null -ne $Request.Body.$Protocol) {
            $CmdParams[$Protocol] = [System.Convert]::ToBoolean($Request.Body.$Protocol)
        }
    }

    # SMTP client authentication can only be turned off via this endpoint. Drop an enable
    # attempt (SmtpClientAuthenticationDisabled = $false) but still apply the other protocols.
    $Warnings = [System.Collections.Generic.List[string]]::new()
    if ($CmdParams.ContainsKey('SmtpClientAuthenticationDisabled') -and $CmdParams['SmtpClientAuthenticationDisabled'] -eq $false) {
        $null = $CmdParams.Remove('SmtpClientAuthenticationDisabled')
        $Warnings.Add('SMTP Client Authentication can only be disabled, not enabled, and was left unchanged.')
    }

    # Nothing left to apply: return the warning if we dropped one, otherwise a generic message.
    if ($CmdParams.Keys.Count -le 1) {
        $Results = $Warnings.Count -gt 0 ? ($Warnings -join ' ') : 'No CAS protocol settings were supplied.'
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev 'Info'
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ 'Results' = $Results }
            })
    }

    # Human readable summary of the change(s) for logging and the API result.
    $ChangeSummary = ($CmdParams.GetEnumerator() | Where-Object { $_.Key -ne 'Identity' } | ForEach-Object {
            '{0} = {1}' -f $_.Key, $_.Value
        }) -join ', '

    try {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-CASMailbox' -cmdParams $CmdParams
        $Results = "Successfully set CAS settings for $DisplayName ($ChangeSummary)"
        if ($Warnings.Count -gt 0) {
            $Results = '{0}. {1}' -f $Results, ($Warnings -join ' ')
        }
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to set CAS settings for $DisplayName. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Results }
        })
}
