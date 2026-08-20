function Invoke-ExecQuarantineManagement {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    # Interact with query parameters or the body of the request.
    try {
        $TenantFilter = $Request.Body.tenantFilter | Select-Object -First 1
        $ActionType = $Request.Body.Type | Select-Object -First 1
        $AllowSender = $Request.Body.AllowSender -eq $true
        $RecipientAddresses = @($Request.Body.RecipientAddress | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $UserRecipients = @(
            $RecipientAddresses |
                ForEach-Object { $_ -split '[,;]' } |
                ForEach-Object { $_.Trim() } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Select-Object -Unique
        )
        $params = @{}

        if ($Request.Body.Identity -is [string]) {
            $params['Identity'] = $Request.Body.Identity
        } else {
            $params['Identities'] = $Request.Body.Identity
            # For -Identities, Exchange requires -Identity to be present, but ignores its value.
            $params['Identity'] = '000'
        }

        # Delete is a separate cmdlet; Release-QuarantineMessage only accepts Release/Request/Approve/Deny.
        if ($ActionType -eq 'Delete') {
            $Cmdlet = 'Delete-QuarantineMessage'
        } else {
            $Cmdlet = 'Release-QuarantineMessage'
            if ($ActionType -eq 'Release') {
                $params['ReleaseToAll'] = $true
            } else {
                $params['ActionType'] = $ActionType
                if ($ActionType -eq 'Deny' -and $UserRecipients.Count -gt 0) {
                    $params['User'] = $UserRecipients
                }
            }
        }
        New-ExoRequest -tenantid $TenantFilter -cmdlet $Cmdlet -cmdParams $params

        # AllowSender via HostedContentFilterPolicy since -AllowSender switch fails in REST API
        if ($AllowSender) {
            try {
                $SenderAddress = $Request.Body.SenderAddress
                $PolicyName = $Request.Body.PolicyName
                if ([string]::IsNullOrEmpty($SenderAddress) -or [string]::IsNullOrEmpty($PolicyName)) {
                    if ($Request.Body.Identity -is [string]) {
                        $QuarantineMessage = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-QuarantineMessage' -cmdParams @{ Identity = $Request.Body.Identity }
                        if ([string]::IsNullOrEmpty($SenderAddress)) { $SenderAddress = $QuarantineMessage.SenderAddress }
                        if ([string]::IsNullOrEmpty($PolicyName)) { $PolicyName = $QuarantineMessage.PolicyName }
                    }
                }
                if (-not [string]::IsNullOrEmpty($SenderAddress) -and -not [string]::IsNullOrEmpty($PolicyName)) {
                    $CurrentPolicy = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-HostedContentFilterPolicy' -cmdParams @{ Identity = $PolicyName }
                    $CurrentSenders = @($CurrentPolicy.AllowedSenders.Sender.Address | Where-Object { $_ })
                    if ($SenderAddress -notin $CurrentSenders) {
                        $UpdatedSenders = @($CurrentSenders + $SenderAddress)
                        New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-HostedContentFilterPolicy' -cmdParams @{
                            Identity       = $PolicyName
                            AllowedSenders = $UpdatedSenders
                        }
                    }
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Added $SenderAddress to allowed senders on policy $PolicyName" -Sev 'Info'
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to add sender to allow list: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
            }
        }

        $Results = [pscustomobject]@{'Results' = "Successfully processed $($Request.Body.Identity)" }
        $StatusCode = [HttpStatusCode]::OK
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Successfully processed Quarantine ID $($Request.Body.Identity)" -Sev 'Info'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Quarantine Management failed: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Results = [pscustomobject]@{'Results' = "Failed. $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::BadRequest
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })

}
