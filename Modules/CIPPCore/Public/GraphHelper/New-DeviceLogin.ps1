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

    # The device code request and the token poll have to agree on both authority and scope.
    # The authority previously diverged - the poll was hard-coded to /organizations while the
    # device code request honoured -TenantId - which silently breaks any tenant-scoped login.
    $Authority = if ($TenantId) { $TenantId } else { 'organizations' }

    # Callers vary in whether they already include the OIDC scopes, so union them in rather
    # than appending unconditionally, which sent them twice on the wire.
    $ScopeList = [System.Collections.Generic.List[string]]@($scope -split '\s+' | Where-Object { $_ })
    foreach ($RequiredScope in @('offline_access', 'profile', 'openid')) {
        if (-not $ScopeList.Contains($RequiredScope)) { $ScopeList.Add($RequiredScope) }
    }
    $RequestScope = $ScopeList -join ' '

    if ($FirstLogon) {
        $Body = @{
            client_id = $Clientid
            scope     = $RequestScope
        }
        $ReturnCode = Invoke-CIPPRestMethod -Uri "https://login.microsoftonline.com/$Authority/oauth2/v2.0/devicecode" -Method POST -Body $Body -ContentType 'application/x-www-form-urlencoded'
    } else {
        $Body = @{
            client_id   = $Clientid
            scope       = $RequestScope
            grant_type  = 'device_code'
            device_code = $device_code
        }
        # Return the whole response, success or not. Collapsing failures to $Checking.error
        # threw away error_description, which is where the AADSTS code lives - so a device
        # code sign-in blocked by security defaults or a Conditional Access authentication
        # flows policy surfaced as an unexplained failure. Callers distinguish the two cases
        # by testing for refresh_token.
        $ReturnCode = Invoke-CIPPRestMethod -SkipHttpErrorCheck -Uri "https://login.microsoftonline.com/$Authority/oauth2/v2.0/token" -Method POST -Body $Body -ContentType 'application/x-www-form-urlencoded'
    }
    return $ReturnCode
}
