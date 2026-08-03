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

    # Legacy fork callers (user actions, exchange info card) send user + enable + protocol(s).
    if ($Request.Body.user) {
        try {
            Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

            $Username = $Request.Body.user
            $Enable = [bool]$Request.Body.enable

            $ProtocolsInput = if ($Request.Body.protocols) {
                $Request.Body.protocols
            } else {
                $Request.Body.protocol
            }

            $ProtocolList = @($ProtocolsInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

            $ProtocolMap = @{
                'EWS'        = 'EwsEnabled'
                'MAPI'       = 'MAPIEnabled'
                'OWA'        = 'OWAEnabled'
                'IMAP'       = 'ImapEnabled'
                'POP'        = 'PopEnabled'
                'ActiveSync' = 'ActiveSyncEnabled'
                # SMTP client auth is inverted in EXO: the parameter disables it, so enable=false
                # from the UI maps to SmtpClientAuthenticationDisabled=true.
                'SMTP'       = 'SmtpClientAuthenticationDisabled'
            }

            foreach ($Protocol in $ProtocolList) {
                if (-not $ProtocolMap.ContainsKey($Protocol)) {
                    throw "Invalid protocol specified: $Protocol. Valid protocols are: $($ProtocolMap.Keys -join ', ')"
                }
            }

            $CmdParams = @{
                Identity = $Username
            }
            foreach ($Protocol in $ProtocolList) {
                $ParamName = $ProtocolMap[$Protocol]
                $CmdParams[$ParamName] = $Protocol -eq 'SMTP' ? (-not $Enable) : $Enable
            }

            $Results = try {
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-CASMailbox' -cmdParams $CmdParams
                $StatusText = if ($Enable) { 'enabled' } else { 'disabled' }
                $ProtocolNames = $ProtocolList -join ', '
                $Message = "Successfully $StatusText $ProtocolNames for $Username"
                Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Info' -tenant $TenantFilter
                $Message
            } catch {
                $ProtocolNames = $ProtocolList -join ', '
                $NormalizedError = (Get-CippException -Exception $_).NormalizedError
                $ErrorMessage = "Failed to update $ProtocolNames for $Username`: $NormalizedError"
                Write-LogMessage -headers $Headers -API $APIName -message "Failed to set $ProtocolNames for $Username`: $($_.Exception.Message)" -Sev 'Error' -tenant $TenantFilter
                throw $ErrorMessage
            }

            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = @{ 'Results' = @($Results) }
                })
        } catch {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = @{ 'Results' = @("$((Get-CippException -Exception $_).NormalizedError)") }
                })
        }
    }

    # Upstream table action callers send Identity + per-protocol boolean flags.
    $Identity = $Request.Body.Identity
    $DisplayName = $Request.Body.DisplayName ?? $Identity

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

    $CmdParams = @{ Identity = $Identity }
    foreach ($Protocol in $ValidProtocols) {
        if ($null -ne $Request.Body.$Protocol) {
            $CmdParams[$Protocol] = [System.Convert]::ToBoolean($Request.Body.$Protocol)
        }
    }

    # SmtpClientAuthenticationDisabled is inverted ($true = SMTP AUTH off) but both values
    # are valid per-mailbox overrides — $false re-enables AUTH for devices/LOB apps even when
    # org TransportConfig has SMTP AUTH disabled.
    if ($CmdParams.Keys.Count -le 1) {
        $Results = 'No CAS protocol settings were supplied.'
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev 'Info'
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ 'Results' = $Results }
            })
    }

    $ChangeSummary = ($CmdParams.GetEnumerator() | Where-Object { $_.Key -ne 'Identity' } | ForEach-Object {
            '{0} = {1}' -f $_.Key, $_.Value
        }) -join ', '

    try {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-CASMailbox' -cmdParams $CmdParams
        $Results = "Successfully set CAS settings for $DisplayName ($ChangeSummary)"
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
