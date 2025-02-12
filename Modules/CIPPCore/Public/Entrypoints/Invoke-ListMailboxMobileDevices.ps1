using namespace System.Net

Function Invoke-ListMailboxMobileDevices {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $Mailbox = $Request.Query.Mailbox

    Write-Host $TenantFilter
    Write-Host $Mailbox

    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Mailbox)
    $base64IdentityParam = [Convert]::ToBase64String($Bytes)

    try {
        $GraphRequest = New-GraphGetRequest -uri "https://outlook.office365.com:443/adminapi/beta/$($TenantFilter)/mailbox('$($base64IdentityParam)')/MobileDevice/Exchange.GetMobileDeviceStatistics()/?IsEncoded=True" -Tenantid $tenantfilter -scope ExchangeOnline | Select-Object @{ Name = 'clientType'; Expression = { $_.ClientType } },
        @{ Name = 'clientVersion'; Expression = { $_.ClientVersion } },
        @{ Name = 'deviceAccessState'; Expression = { $_.DeviceAccessState } },
        @{ Name = 'deviceFriendlyName'; Expression = { if ([string]::IsNullOrEmpty($_.DeviceFriendlyName)) { 'Unknown' }else { $_.DeviceFriendlyName } } },
        @{ Name = 'deviceModel'; Expression = { $_.DeviceModel } },
        @{ Name = 'deviceOS'; Expression = { $_.DeviceOS } },
        @{ Name = 'deviceType'; Expression = { $_.DeviceType } },
        @{ Name = 'firstSync'; Expression = { $_.FirstSyncTime.toString() } },
        @{ Name = 'lastSyncAttempt'; Expression = { $_.LastSyncAttemptTime.toString() } },
        @{ Name = 'lastSuccessSync'; Expression = { $_.LastSuccessSync.toString() } },
        @{ Name = 'status'; Expression = { $_.Status } },
        @{ Name = 'deviceID'; Expression = { $_.deviceID } },
        @{ Name = 'Guid'; Expression = { $_.Guid } }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })

}
