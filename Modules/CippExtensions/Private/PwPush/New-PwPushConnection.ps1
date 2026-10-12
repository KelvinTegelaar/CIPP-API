function New-PwPushConnection {
    <#
    .SYNOPSIS
        Builds a PWPush connection object from the extension configuration.
    .DESCRIPTION
        Returns BaseUrl, request headers and the detected API version for one call. Built fresh
        every time so config changes and key rotations apply immediately in every runspace.
    .PARAMETER Configuration
        The PWPush section of the extension configuration.
    .PARAMETER FullConfiguration
        The whole parsed extension configuration (for the CFZTNA settings).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Configuration,
        $FullConfiguration
    )

    $BaseUrl = if ([string]::IsNullOrWhiteSpace($Configuration.BaseUrl)) { 'https://pwpush.com' } else { "$($Configuration.BaseUrl)".Trim().TrimEnd('/') }

    $Headers = @{ Accept = 'application/json' }
    if ($Configuration.CFEnabled -eq $true -and $FullConfiguration.CFZTNA.Enabled -eq $true) {
        $Headers['CF-Access-Client-Id'] = "$($FullConfiguration.CFZTNA.ClientId)"
        $Headers['CF-Access-Client-Secret'] = "$(Get-ExtensionAPIKey -Extension 'CFZTNA')"
    }

    # Probe before adding auth: an unrecognised token is rejected even on anonymous endpoints
    $Version = Get-CIPPPwPushVersion -BaseUrl $BaseUrl -Headers $Headers

    # Bearer works on v1 and v2; legacy email-based configs keep their key as the token
    if ($Configuration.UseBearerAuth -eq $true -or -not [string]::IsNullOrEmpty($Configuration.EmailAddress)) {
        $ApiKey = Get-ExtensionAPIKey -Extension 'PWPush'
        if (-not [string]::IsNullOrEmpty($ApiKey)) { $Headers['Authorization'] = "Bearer $ApiKey" }
    }

    [pscustomobject]@{
        BaseUrl    = $BaseUrl
        Headers    = $Headers
        ApiVersion = $Version.ApiVersion
        Edition    = $Version.Edition
        Features   = $Version.Features
    }
}
