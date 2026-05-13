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
    if ($FirstLogon) {
        $Body = @{
            client_id = $Clientid
            scope     = "$scope offline_access profile openid"
        }
        if ($TenantID) {
            $ReturnCode = Invoke-CIPPRestMethod -Uri "https://login.microsoftonline.com/$($TenantID)/oauth2/v2.0/devicecode" -Method POST -Body $Body -ContentType 'application/x-www-form-urlencoded'
        } else {
            $ReturnCode = Invoke-CIPPRestMethod -Uri 'https://login.microsoftonline.com/organizations/oauth2/v2.0/devicecode' -Method POST -Body $Body -ContentType 'application/x-www-form-urlencoded'
        }
    } else {
        $Body = @{
            client_id   = $Clientid
            scope       = "$scope offline_access profile openid"
            grant_type  = 'device_code'
            device_code = $device_code
        }
        $Checking = Invoke-CIPPRestMethod -SkipHttpErrorCheck -Uri 'https://login.microsoftonline.com/organizations/oauth2/v2.0/token' -Method POST -Body $Body -ContentType 'application/x-www-form-urlencoded'
        if ($checking.refresh_token) {
            $ReturnCode = $Checking
        } else {
            $returncode = $Checking.error
        }
    }
    return $ReturnCode
}
