function Invoke-CIPPPwPushRequest {
    <#
    .SYNOPSIS
        Sends one request to the Password Pusher API.
    .DESCRIPTION
        Wraps Invoke-CIPPRestMethod without following redirects, retries HTTP 429 (honouring
        Retry-After) up to three attempts, and turns any other non-2xx status into an error that
        never includes the response body.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [ValidateSet('GET', 'POST')][string]$Method = 'GET',
        [Parameter(Mandatory)][hashtable]$Headers,
        [string]$Body
    )

    $Request = @{
        Uri                = $Uri
        Method             = $Method
        Headers            = $Headers
        TimeoutSec         = 30
        # A followed redirect turns the POST into a body-less GET, so surface it instead
        MaximumRedirection = 0
        ErrorAction        = 'Stop'
    }
    if ($PSBoundParameters.ContainsKey('Body')) {
        $Request.Body = $Body
        $Request.ContentType = 'application/json'
    }

    $MaxAttempts = 3
    for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
        try {
            return Invoke-CIPPRestMethod @Request
        } catch {
            # Status variables do not cross module boundaries, so read the status off the error
            $Response = $_.Exception.Response
            if (-not $Response) { throw }
            $StatusCode = [int]$Response.StatusCode
        }

        if ($StatusCode -in 301, 302, 303, 307, 308) {
            $Location = "$($Response.Headers['Location'])"
            $Target = if ($Location) { [uri]::new([uri]$Uri, $Location) }
            $TargetHost = if ($Target) { '{0}://{1}' -f $Target.Scheme, $Target.Authority } else { 'another address' }
            throw "PWPush URL redirects to $TargetHost - set that as the PWPush URL."
        }

        if ($StatusCode -eq 429 -and $Attempt -lt $MaxAttempts) {
            $RetryAfter = 0
            $Delay = if ([int]::TryParse("$($Response.Headers['Retry-After'])", [ref]$RetryAfter) -and $RetryAfter -ge 1 -and $RetryAfter -le 60) { $RetryAfter } else { 2 * $Attempt }
            Start-Sleep -Seconds $Delay
            continue
        }

        # Field names only: a validation body can echo the pushed payload
        $Fields = if ($StatusCode -in 400, 422) {
            try { @(($Response.Content | ConvertFrom-Json -ErrorAction Stop).PSObject.Properties.Name) -join ', ' } catch { $null }
        }
        $Detail = if ($Fields) { " ($Fields)" } elseif ($StatusCode -eq 401) { ' (check the PWPush API key)' }
        throw "PWPush API returned HTTP $StatusCode$Detail"
    }
}
