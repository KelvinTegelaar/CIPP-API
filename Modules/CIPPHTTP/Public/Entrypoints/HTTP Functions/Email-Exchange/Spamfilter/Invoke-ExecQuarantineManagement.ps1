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
    # Interact with query parameters or the body of the request.
    try {
        $TenantFilter = $Request.Body.tenantFilter | Select-Object -First 1
        $ActionType = $Request.Body.Type | Select-Object -First 1
        $AllowSender = $Request.Body.AllowSender -eq $true
        $params = @{}

        if ($ActionType -eq 'Release') {
            $params['ReleaseToAll'] = $true
        } else {
            $params['ActionType'] = $ActionType
        }

        if ($Request.Body.Identity -is [string]) {
            $params['Identity'] = $Request.Body.Identity
        } else {
            $params['Identities'] = $Request.Body.Identity
            $params['Identity'] = '000'
        }
        New-ExoRequest -tenantid $TenantFilter -cmdlet 'Release-QuarantineMessage' -cmdParams $params

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
                    Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $TenantFilter -message "Added $SenderAddress to allowed senders on policy $PolicyName" -Sev 'Info'
                }
            } catch {
                Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $TenantFilter -message "Failed to add sender to allow list: $($_.Exception.Message)" -Sev 'Error' -LogData $_
            }
        }

        $Results = [pscustomobject]@{'Results' = "Successfully processed $($Request.Body.Identity)" }
        Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $TenantFilter -message "Successfully processed Quarantine ID $($Request.Body.Identity)" -Sev 'Info'
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $TenantFilter -message "Quarantine Management failed: $($_.Exception.Message)" -Sev 'Error' -LogData $_
        $Results = [pscustomobject]@{'Results' = "Failed. $($_.Exception.Message)" }
    }
    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}
