function Get-CIPPPwPushVersion {
    <#
    .SYNOPSIS
        Detects which Password Pusher API version a server speaks.
    .DESCRIPTION
        Probes GET /api/v2/version anonymously: 200 means v2 (with edition and features), 404 means
        v1. Definite answers are remembered per base URL for an hour; any other outcome falls back
        to v1 without being remembered so the next call probes again.
    .PARAMETER BaseUrl
        Server root, e.g. https://eu.pwpush.com
    .PARAMETER Headers
        Non-auth headers the server needs to be reached at all (e.g. Cloudflare Access). Never pass
        an Authorization header: an unknown token is rejected even on anonymous endpoints.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [hashtable]$Headers = @{}
    )

    $BaseUrl = $BaseUrl.Trim().TrimEnd('/')
    # The only module state: per-runspace probe memo, safe to diverge between runspaces
    if ($null -eq $script:CIPPPwPushVersionCache) { $script:CIPPPwPushVersionCache = [hashtable]::Synchronized(@{}) }
    $Cached = $script:CIPPPwPushVersionCache[$BaseUrl]
    if ($Cached -and $Cached.Expires -gt [datetime]::UtcNow) { return $Cached.Result }

    $ProbeHeaders = @{} + $Headers
    $ProbeHeaders['Accept'] = 'application/json'
    $StatusCode = $null
    $Response = $null
    try {
        $Response = Invoke-CIPPRestMethod -Uri "$BaseUrl/api/v2/version" -Headers $ProbeHeaders -TimeoutSec 15 -ErrorAction Stop
        $StatusCode = 200
    } catch {
        $StatusCode = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode }
    }

    if ($StatusCode -eq 200 -and $Response.api_version) {
        $Result = [pscustomobject]@{ ApiVersion = 'v2'; Edition = $Response.edition; Features = $Response.features }
    } else {
        $Result = [pscustomobject]@{ ApiVersion = 'v1'; Edition = $null; Features = $null }
        if ($StatusCode -ne 404) {
            Write-LogMessage -API PwPush -Message "Could not detect the PWPush API version at $BaseUrl (status $StatusCode), assuming v1" -Sev Warning
            return $Result
        }
    }
    $script:CIPPPwPushVersionCache[$BaseUrl] = @{ Result = $Result; Expires = [datetime]::UtcNow.AddHours(1) }
    return $Result
}
