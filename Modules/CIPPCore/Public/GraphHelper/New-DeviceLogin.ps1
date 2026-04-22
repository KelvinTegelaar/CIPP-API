function New-DeviceLogin {
    <#
    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param (
        [string]$clientid,
        [string]$scope,
        [switch]$FirstLogon,
        [string]$device_code,
        [string]$TenantId
    )
    $encodedscope = [uri]::EscapeDataString($scope)
    if ($FirstLogon) {
        if ($TenantID) {
            $ReturnCode = Invoke-CIPPRestMethod -Uri "https://login.microsoftonline.com/$($TenantID)/oauth2/v2.0/devicecode" -Method POST -Body "client_id=$($Clientid)&scope=$encodedscope+offline_access+profile+openid"

        } else {
            $ReturnCode = Invoke-CIPPRestMethod -Uri 'https://login.microsoftonline.com/organizations/oauth2/v2.0/devicecode' -Method POST -Body "client_id=$($Clientid)&scope=$encodedscope+offline_access+profile+openid"
        }
    } else {
        $Checking = Invoke-CIPPRestMethod -SkipHttpErrorCheck -Uri 'https://login.microsoftonline.com/organizations/oauth2/v2.0/token' -Method POST -Body "client_id=$($Clientid)&scope=$encodedscope+offline_access+profile+openid&grant_type=device_code&device_code=$($device_code)"
        if ($checking.refresh_token) {
            $ReturnCode = $Checking
        } else {
            $returncode = $Checking.error
        }
    }
    return $ReturnCode
}