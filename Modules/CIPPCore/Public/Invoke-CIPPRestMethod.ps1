function Invoke-CIPPRestMethod {
    <#
    .SYNOPSIS
        Drop-in replacement for Invoke-RestMethod using a pooled .NET HttpClient.

    .DESCRIPTION
        Wraps CIPP.CIPPRestClient (loaded via profile.ps1) to provide connection
        pooling across all runspaces in the worker process. Handles all usage
        patterns found in CIPP core paths:

          - New-GraphGetRequest   (GET + ResponseHeadersVariable + pagination)
          - New-GraphBulkRequest  (POST $batch)
          - New-ExoRequest        (POST + MaximumRedirection 0 for compliance URL)
          - New-ExoBulkRequest    (POST $batch EXO)

        JSON responses are automatically deserialized (ConvertFrom-Json -Depth 100).
        Non-JSON responses are returned as raw strings.
        Hashtable bodies are form-encoded when no ContentType is set (matches
        Invoke-RestMethod default behaviour for OAuth token requests etc.).

    .PARAMETER Uri
        Request URI.

    .PARAMETER Method
        HTTP method. Defaults to GET.

    .PARAMETER Body
        Request body. Hashtables with no ContentType → form-encoded.
        Hashtables/PSObjects with JSON ContentType → JSON serialized.
        Strings → sent verbatim.

    .PARAMETER Headers
        Request headers hashtable.

    .PARAMETER ContentType
        Content-Type header. Defaults to application/json when a non-hashtable
        Body is supplied.

    .PARAMETER SkipHttpErrorCheck
        Non-2xx responses do not throw; raw result is returned.

    .PARAMETER ResponseHeadersVariable
        Variable name in the caller's scope to receive response headers hashtable.
        Matches Invoke-RestMethod behaviour exactly.

    .PARAMETER StatusCodeVariable
        Variable name in the caller's scope to receive the integer HTTP status code.

    .PARAMETER TimeoutSec
        Per-request timeout in seconds. 0 = infinite. Defaults to 100.

    .PARAMETER MaximumRedirection
        Maximum number of redirects to follow. 0 = do not follow any redirects
        (used by New-ExoRequest compliance URL discovery). Defaults to -1 (follow
        up to 10 redirects, matching default Invoke-RestMethod behaviour).

    .PARAMETER UseLegacyInvokeRestMethod
        Bypass the pooled client entirely and use the built-in Invoke-RestMethod.
        Use for multipart/form-data or other edge cases not handled by this wrapper.
    #>

    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('Url')]
        [uri] $Uri,

        [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS')]
        [string] $Method = 'GET',

        [object] $Body,

        [hashtable] $Headers = @{},

        [string] $ContentType,

        [switch] $SkipHttpErrorCheck,

        [string] $ResponseHeadersVariable,

        [string] $StatusCodeVariable,

        [int] $TimeoutSec = 100,

        [int] $MaximumRedirection = -1,

        [switch] $UseLegacyInvokeRestMethod
    )

    # ------------------------------------------------------------------
    # Escape hatch — env var kill switch, missing pooled client type,
    # or per-call legacy switch
    # ------------------------------------------------------------------
    $HasCippRestClient = $null -ne ('CIPP.CIPPRestClient' -as [type])
    if ($UseLegacyInvokeRestMethod -or $env:DisableCIPPRestMethod -eq 'true' -or -not $HasCippRestClient) {
        $LegacyParams = @{
            Uri         = $Uri
            Method      = $Method
            Headers     = $Headers
            ErrorAction = $ErrorActionPreference
        }
        if ($PSBoundParameters.ContainsKey('Body'))        { $LegacyParams['Body']                     = $Body }
        if ($ContentType)                                  { $LegacyParams['ContentType']               = $ContentType }
        if ($SkipHttpErrorCheck)                           { $LegacyParams['SkipHttpErrorCheck']        = $true }
        if ($ResponseHeadersVariable)                      { $LegacyParams['ResponseHeadersVariable']   = $ResponseHeadersVariable }
        if ($StatusCodeVariable)                           { $LegacyParams['StatusCodeVariable']        = $StatusCodeVariable }
        if ($TimeoutSec -gt 0)                             { $LegacyParams['TimeoutSec']                = $TimeoutSec }
        if ($MaximumRedirection -ge 0)                     { $LegacyParams['MaximumRedirection']        = $MaximumRedirection }
        return Microsoft.PowerShell.Utility\Invoke-RestMethod @LegacyParams
    }

    # ------------------------------------------------------------------
    # Normalise ContentType
    # ------------------------------------------------------------------
    if ([string]::IsNullOrWhiteSpace($ContentType)) { $ContentType = $null }

    # ------------------------------------------------------------------
    # Serialise body
    # Mirrors Invoke-RestMethod behaviour:
    #   String                         → verbatim
    #   Hashtable, no ContentType      → application/x-www-form-urlencoded
    #   Hashtable, JSON ContentType    → JSON
    #   PSObject / array               → JSON
    # ------------------------------------------------------------------
    [string] $BodyString = $null

    if ($PSBoundParameters.ContainsKey('Body')) {
        if ($null -eq $Body) {
            $BodyString = ''
        } elseif ($Body -is [string]) {
            $BodyString = $Body
        } elseif (
            ($Body -is [System.Collections.IDictionary]) -and
            ($null -eq $ContentType -or $ContentType -like 'application/x-www-form-urlencoded*')
        ) {
            # Form-encode — WebUtility.UrlEncode encodes '+' as '%2B' (required for
            # OAuth client secrets which frequently contain '+')
            $Pairs = foreach ($Key in $Body.Keys) {
                '{0}={1}' -f [System.Net.WebUtility]::UrlEncode([string]$Key),
                               [System.Net.WebUtility]::UrlEncode([string]$Body[$Key])
            }
            $BodyString  = $Pairs -join '&'
            $ContentType = 'application/x-www-form-urlencoded'
        } else {
            $BodyString = $Body | ConvertTo-Json -Depth 20 -Compress
            if ($null -eq $ContentType) { $ContentType = 'application/json; charset=utf-8' }
        }
    }

    # ------------------------------------------------------------------
    # Build managed header dictionary for C#
    # ------------------------------------------------------------------
    $ManagedHeaders = [System.Collections.Generic.Dictionary[string, string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($Key in $Headers.Keys) {
        $ManagedHeaders[$Key] = [string]$Headers[$Key]
    }

    # ------------------------------------------------------------------
    # Invoke the pooled C# client
    # Always skip error check in C# so we get the full HttpResult back
    # (including error response bodies). PS handles error throwing below.
    # ------------------------------------------------------------------
    try {
        $Result = [CIPP.CIPPRestClient]::Send(
            [string]$Uri,
            $Method,
            $BodyString,
            $ManagedHeaders,
            $(if ($ContentType) { $ContentType } else { $null }),
            $true,
            $TimeoutSec,
            $MaximumRedirection
        )
    } catch {
        # PowerShell wraps .NET static method exceptions in MethodInvocationException.
        # The actual HttpRequestException / OperationCanceledException is the InnerException.
        $InnerEx = $_.Exception.InnerException ?? $_.Exception

        if ($InnerEx -is [System.OperationCanceledException]) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    [System.TimeoutException]::new("The request to '$Uri' timed out after ${TimeoutSec}s.", $InnerEx),
                    'RequestTimeout',
                    [System.Management.Automation.ErrorCategory]::OperationTimeout,
                    $Uri
                )
            )
            return
        }

        if ($InnerEx -is [System.Net.Http.HttpRequestException]) {
            $PSCmdlet.ThrowTerminatingError(
                [System.Management.Automation.ErrorRecord]::new(
                    $InnerEx,
                    'HttpRequestFailed',
                    [System.Management.Automation.ErrorCategory]::ConnectionError,
                    $Uri
                )
            )
            return
        }

        # Unknown exception type — re-throw with the inner exception for a cleaner message
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                $InnerEx,
                'HttpRequestFailed',
                [System.Management.Automation.ErrorCategory]::ConnectionError,
                $Uri
            )
        )
        return
    }

    # ------------------------------------------------------------------
    # Surface status code and headers to caller's scope
    # Matches Invoke-RestMethod behaviour exactly
    # ------------------------------------------------------------------
    if ($StatusCodeVariable) {
        Set-Variable -Scope 1 -Name $StatusCodeVariable -Value $Result.StatusCode
    }

    if ($ResponseHeadersVariable) {
        # Convert to a regular hashtable so callers can dot-index headers
        # the same way they do with Invoke-RestMethod's output
        $HeadersHt = @{}
        foreach ($Key in $Result.ResponseHeaders.Keys) {
            $Values = $Result.ResponseHeaders[$Key]
            # Invoke-RestMethod returns arrays for multi-value headers,
            # single string for single-value headers — match that behaviour
            $HeadersHt[$Key] = if ($Values.Count -eq 1) { $Values[0] } else { $Values }
        }
        Set-Variable -Scope 1 -Name $ResponseHeadersVariable -Value $HeadersHt
    }

    # ------------------------------------------------------------------
    # Error handling — throw with response body in ErrorDetails
    # ------------------------------------------------------------------
    if (-not $SkipHttpErrorCheck -and -not $Result.IsSuccess) {
        $ErrorMessage = "Response status code does not indicate success: $($Result.StatusCode)"
        $Exception = [System.Net.Http.HttpRequestException]::new($ErrorMessage)
        $ErrorRecord = [System.Management.Automation.ErrorRecord]::new($Exception, 'WebCmdletWebResponseException', [System.Management.Automation.ErrorCategory]::InvalidOperation, $Uri)
        if (-not [string]::IsNullOrWhiteSpace($Result.Content)) {
            $ErrorRecord.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Result.Content)
        }
        $PSCmdlet.ThrowTerminatingError($ErrorRecord)
        return
    }

    # ------------------------------------------------------------------
    # Return — deserialize JSON or return raw string
    # Empty body → null (matches Invoke-RestMethod on 204 No Content etc.)
    # ------------------------------------------------------------------
    if ([string]::IsNullOrWhiteSpace($Result.Content)) {
        return $null
    }

    if ($Result.IsJson) {
        try {
            return $Result.Content | ConvertFrom-Json -Depth 100
        } catch {
            # Malformed JSON — return raw so callers can handle it
            return $Result.Content
        }
    }

    return $Result.Content
}
