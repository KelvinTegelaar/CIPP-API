function Invoke-ExecIRMConfiguration {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    .DESCRIPTION
        Enables or disables Microsoft Purview Message Encryption for a tenant by setting AzureRMSLicensingEnabled, or runs Test-IRMConfiguration to verify that encryption and decryption work end to end.
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
                $AzureRMSLicensingEnabled = [System.Convert]::ToBoolean($Request.Body.AzureRMSLicensingEnabled)
                $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-IRMConfiguration' -cmdParams @{ AzureRMSLicensingEnabled = $AzureRMSLicensingEnabled }
                $Results = "Successfully $(if ($AzureRMSLicensingEnabled) { 'enabled' } else { 'disabled' }) Microsoft Purview Message Encryption."
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
