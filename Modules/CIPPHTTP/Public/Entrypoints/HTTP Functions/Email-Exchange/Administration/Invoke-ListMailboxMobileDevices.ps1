Function Invoke-ListMailboxMobileDevices {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    .DESCRIPTION
        Lists mobile devices associated with a specific Exchange Online mailbox.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $Mailbox = $Request.Query.Mailbox

    Write-Information $TenantFilter
    Write-Information $Mailbox

    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Mailbox)
    $base64IdentityParam = [Convert]::ToBase64String($Bytes)

    try {
        $Devices = New-GraphGetRequest -uri "https://outlook.office365.com:443/adminapi/beta/$($TenantFilter)/mailbox('$($base64IdentityParam)')/MobileDevice/Exchange.GetMobileDeviceStatistics()/?IsEncoded=True" -Tenantid $TenantFilter -scope ExchangeOnline
        $DateFormat = 'yyyy-MM-ddTHH:mm:ssZ'
        $GraphRequest = foreach ($Device in $Devices) {
            [PSCustomObject]@{
                clientType                 = $Device.ClientType
                clientVersion              = $Device.ClientVersion
                deviceAccessState          = $Device.DeviceAccessState
                deviceAccessStateReason    = $Device.DeviceAccessStateReason
                deviceFriendlyName         = if ([string]::IsNullOrEmpty($Device.DeviceFriendlyName)) { 'Unknown' } else { $Device.DeviceFriendlyName }
                deviceModel                = $Device.DeviceModel
                deviceOS                   = $Device.DeviceOS
                deviceType                 = $Device.DeviceType
                firstSync                  = if ($Device.FirstSyncTime) { ([datetime]$Device.FirstSyncTime).ToUniversalTime().ToString($DateFormat) }
                lastSyncAttempt            = if ($Device.LastSyncAttemptTime) { ([datetime]$Device.LastSyncAttemptTime).ToUniversalTime().ToString($DateFormat) }
                lastSuccessSync            = if ($Device.LastSuccessSync) { ([datetime]$Device.LastSuccessSync).ToUniversalTime().ToString($DateFormat) }
                status                     = $Device.Status
                accountOnlyWipeRequestTime = if ($Device.AccountOnlyDeviceWipeRequestTime) { ([datetime]$Device.AccountOnlyDeviceWipeRequestTime).ToUniversalTime().ToString($DateFormat) }
                accountOnlyWipeAckTime     = if ($Device.AccountOnlyDeviceWipeAckTime) { ([datetime]$Device.AccountOnlyDeviceWipeAckTime).ToUniversalTime().ToString($DateFormat) }
                deviceID                   = $Device.DeviceID
                Guid                       = $Device.Guid
            }
        }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
        $GraphRequest = $ErrorMessage
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })

}
