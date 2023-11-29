function Read-JwtAccessDetails {
    <#
    .SYNOPSIS
    Parse Microsoft JWT access tokens

    .DESCRIPTION
    Extract JWT access token details for verification

    .PARAMETER Token
    Token to get details for

    #>
    [cmdletbinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Token
    )

    # Default token object
    $TokenDetails = [PSCustomObject]@{
        AppId             = ''
        AppName           = ''
        Audience          = ''
        AuthMethods       = ''
        IPAddress         = ''
        Name              = ''
        Scope             = ''
        TenantId          = ''
        UserPrincipalName = ''
    }

    if (!$Token.Contains('.') -or !$token.StartsWith('eyJ')) { return $TokenDetails }

    # Get token payload
    $tokenPayload = $token.Split('.')[1].Replace('-', '+').Replace('_', '/')
    while ($tokenPayload.Length % 4) {
        $tokenPayload = '{0}=' -f $tokenPayload
    }

    # Convert base64 to json to object
    $tokenByteArray = [System.Convert]::FromBase64String($tokenPayload)
    $tokenArray = [System.Text.Encoding]::ASCII.GetString($tokenByteArray)
    $TokenObj = $tokenArray | ConvertFrom-Json

    # Convert token details to human readable
    $TokenDetails.AppId = $TokenObj.appid
    $TokenDetails.AppName = $TokenObj.app_displayname
    $TokenDetails.Audience = $TokenObj.aud
    $TokenDetails.AuthMethods = $TokenObj.amr
    $TokenDetails.IPAddress = $TokenObj.ipaddr
    $TokenDetails.Name = $TokenObj.name
    $TokenDetails.Scope = $TokenObj.scp -split ' '
    $TokenDetails.TenantId = $TokenObj.tid
    $TokenDetails.UserPrincipalName = $TokenObj.upn

    return $TokenDetails
}