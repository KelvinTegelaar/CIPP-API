function Invoke-ExecIRMConfiguration {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    .DESCRIPTION
        Updates the Microsoft Purview Message Encryption configuration for a tenant (AzureRMSLicensingEnabled, SimplifiedClientAccessEnabled, EnablePdfEncryption, DecryptAttachmentForEncryptOnly, SimplifiedClientAccessDoNotForwardDisabled, SimplifiedClientAccessEncryptOnlyDisabled, TransportDecryptionSetting; only the settings present in the body are changed), or runs Test-IRMConfiguration to verify that encryption and decryption work end to end.
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
                # Only touch the settings the caller sent, so an API client that posts just
                # AzureRMSLicensingEnabled does not silently flip the others. Whitelisted: the body is
                # caller-controlled and goes straight to Set-IRMConfiguration.
                $cmdParams = @{}
                foreach ($Key in 'AzureRMSLicensingEnabled', 'SimplifiedClientAccessEnabled', 'EnablePdfEncryption', 'DecryptAttachmentForEncryptOnly', 'SimplifiedClientAccessDoNotForwardDisabled', 'SimplifiedClientAccessEncryptOnlyDisabled') {
                    if ($null -ne $Request.Body.$Key) { $cmdParams[$Key] = [System.Convert]::ToBoolean($Request.Body.$Key) }
                }
                if ($Request.Body.TransportDecryptionSetting -in 'Disabled', 'Optional', 'Mandatory') {
                    $cmdParams.TransportDecryptionSetting = $Request.Body.TransportDecryptionSetting
                }
                if ($cmdParams.Count -eq 0) {
                    throw 'No message encryption settings were provided.'
                }
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-IRMConfiguration' -cmdParams $cmdParams
                $Applied = ($cmdParams.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name) = $($_.Value)" }) -join ', '
                $Results = "Successfully updated the message encryption configuration: $Applied."
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
