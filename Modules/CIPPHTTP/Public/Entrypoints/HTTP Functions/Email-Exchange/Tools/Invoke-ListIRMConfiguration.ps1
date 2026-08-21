function Invoke-ListIRMConfiguration {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    .DESCRIPTION
        Lists the Information Rights Management (IRM) configuration for a tenant. Used to check whether Microsoft Purview Message Encryption is active and whether an on-premises AD RMS deployment still has to be migrated to Azure RMS first.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter

    try {
        $IRMConfig = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-IRMConfiguration' | Select-Object -First 1

        # Purview Message Encryption is not compatible with on-premises AD RMS. A licensing location
        # that is not an Azure RMS URL means the tenant still points at an AD RMS cluster and has to
        # be migrated before message encryption can be enabled.
        # ponytail: URL-shape heuristic, the only signal Get-IRMConfiguration gives us. Get-AipServiceConfiguration would confirm it, but that needs the AIPService module which CIPP does not ship.
        $LicensingLocation = @($IRMConfig.LicensingLocation | Where-Object { $_ })
        $AdRmsDetected = @($LicensingLocation | Where-Object { $_ -notmatch 'aadrm\.|azurerms|\.microsoft\.(com|us)' }).Count -gt 0

        $Results = [PSCustomObject]@{
            AzureRMSLicensingEnabled       = $IRMConfig.AzureRMSLicensingEnabled
            InternalLicensingEnabled       = $IRMConfig.InternalLicensingEnabled
            ExternalLicensingEnabled       = $IRMConfig.ExternalLicensingEnabled
            SimplifiedClientAccessEnabled  = $IRMConfig.SimplifiedClientAccessEnabled
            TransportDecryptionSetting     = $IRMConfig.TransportDecryptionSetting
            JournalReportDecryptionEnabled = $IRMConfig.JournalReportDecryptionEnabled
            LicensingLocation              = $LicensingLocation
            MessageEncryptionEnabled       = [bool]$IRMConfig.AzureRMSLicensingEnabled
            AdRmsDetected                  = $AdRmsDetected
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Results = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}
