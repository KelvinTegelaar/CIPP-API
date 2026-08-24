function Invoke-ExecIRMConfiguration {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    .DESCRIPTION
        Enables or disables Microsoft Purview Message Encryption for a tenant by setting AzureRMSLicensingEnabled and the Outlook Encrypt button by setting SimplifiedClientAccessEnabled, or runs Test-IRMConfiguration to verify that encryption and decryption work end to end.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $Action = $Request.Body.Action

    try {
        switch ($Action) {
            'Test' {
                $SenderAddress = $Request.Body.Sender
                $RecipientAddress = $Request.Body.Recipient
                if (!$SenderAddress -or !$RecipientAddress) {
                    throw 'A sender and a recipient are required to test the message encryption configuration.'
                }
                $TestResult = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Test-IRMConfiguration' -cmdParams @{ Sender = $SenderAddress; Recipient = $RecipientAddress }
                # Test-IRMConfiguration returns one object per check, the summary lives in the Results property.
                $Results = @($TestResult.Results | Where-Object { $_ })
                if (!$Results) { $Results = @($TestResult | Out-String) }
                Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Tested the message encryption configuration for $SenderAddress" -Sev Info
            }
            'Set' {
                $cmdParams = @{ AzureRMSLicensingEnabled = [System.Convert]::ToBoolean($Request.Body.AzureRMSLicensingEnabled) }
                # Only touch the Encrypt button setting when the caller sent it, so an API client
                # that posts just AzureRMSLicensingEnabled does not silently disable it.
                if ($null -ne $Request.Body.SimplifiedClientAccessEnabled) {
                    $cmdParams.SimplifiedClientAccessEnabled = [System.Convert]::ToBoolean($Request.Body.SimplifiedClientAccessEnabled)
                }
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-IRMConfiguration' -cmdParams $cmdParams
                $ResultParts = [System.Collections.Generic.List[string]]::new()
                $ResultParts.Add("$(if ($cmdParams.AzureRMSLicensingEnabled) { 'enabled' } else { 'disabled' }) Microsoft Purview Message Encryption")
                if ($cmdParams.ContainsKey('SimplifiedClientAccessEnabled')) {
                    $ResultParts.Add("$(if ($cmdParams.SimplifiedClientAccessEnabled) { 'enabled' } else { 'disabled' }) the Outlook Encrypt button")
                }
                $Results = "Successfully $($ResultParts -join ' and ')."
                Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev Info
            }
            default {
                throw "Invalid action: $Action"
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to run the '$Action' action on the message encryption configuration. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Results }
        })
}
