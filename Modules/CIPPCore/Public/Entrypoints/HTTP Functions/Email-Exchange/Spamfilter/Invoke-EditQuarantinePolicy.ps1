using namespace System.Net

function Invoke-EditQuarantinePolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Spamfilter.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter

    if ($Request.Query.Type -eq 'GlobalQuarantinePolicy') {

        $Frequency = $Request.Body.EndUserSpamNotificationFrequency.value ?? $Request.Body.EndUserSpamNotificationFrequency
        # If request EndUserSpamNotificationFrequency it not set to a ISO 8601 timeformat, convert it to one.
        # This happens if the user doesn't change the Notification Frequency value in the UI. Because of a "bug" with setDefaultValue function with the cippApiDialog, where "label" is set to both label and value.
        $EndUserSpamNotificationFrequency = switch ($Frequency) {
            '4 Hours' { 'PT4H' }
            'Daily' { 'P1D' }
            'Weekly' { 'P7D' }
            default { $Frequency }
        }

        $Params = @{
            Identity                                 = $Request.Body.Identity
            # Convert the requested frequency from ISO 8601 to a TimeSpan object
            EndUserSpamNotificationFrequency         = [System.Xml.XmlConvert]::ToTimeSpan($EndUserSpamNotificationFrequency)
            EndUserSpamNotificationCustomFromAddress = $Request.Body.EndUserSpamNotificationCustomFromAddress
            OrganizationBrandingEnabled              = $Request.Body.OrganizationBrandingEnabled
        }
    } else {
        $ReleaseActionPreference = $Request.Body.ReleaseActionPreference.value ?? $Request.Body.ReleaseActionPreference

        $EndUserQuarantinePermissions = @{
            PermissionToBlockSender    = $Request.Body.BlockSender
            PermissionToDelete         = $Request.Body.Delete
            PermissionToPreview        = $Request.Body.Preview
            PermissionToRelease        = $ReleaseActionPreference -eq 'Release' ? $true : $false
            PermissionToRequestRelease = $ReleaseActionPreference -eq 'RequestRelease' ? $true : $false
            PermissionToAllowSender    = $Request.Body.AllowSender
        }

        $Params = @{
            Identity                                = $Request.Body.Identity
            EndUserQuarantinePermissions            = $EndUserQuarantinePermissions
            ESNEnabled                              = $Request.Body.QuarantineNotification
            IncludeMessagesFromBlockedSenderAddress = $Request.Body.IncludeMessagesFromBlockedSenderAddress
            action                                  = $Request.Body.Action ?? 'Set'
        }
    }

    try {
        $Result = Set-CIPPQuarantinePolicy @Params -tenantFilter $TenantFilter -APIName $APIName -Headers $Headers
        $StatusCode = [HttpStatusCode]::OK
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Info
    } catch {
        $Result = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Error -LogData $ErrorMessage
    }

    return @{
        StatusCode = $StatusCode
        Body       = @{ Results = $Result }
    }
}
