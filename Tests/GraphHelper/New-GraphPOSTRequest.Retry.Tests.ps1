# SharePoint answers a busy front end with a 503 and an HTML page, which none of the transient-error message
# matches recognise. It is retryable, so the status code itself has to trigger the retry.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')

    function Get-AuthorisedRequest { param($Uri, $TenantID) $true }
    function Get-GraphToken { param($tenantid, $scope, $AsApp, $SkipCache, [switch]$UseCertificate) @{} }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }
    function Get-CippUserAgent { param([switch]$SharePoint) 'CIPP/test' }
    function Get-NormalizedError { param($Message) $Message }
    function Invoke-CIPPRestMethod { param($Uri, $Method, $Body, $Headers, $ContentType, [switch]$SkipHttpErrorCheck, $ResponseHeadersVariable) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/New-GraphPOSTRequest.ps1')

    function New-BusyException([string]$RetryAfter) {
        $Headers = [System.Collections.Generic.Dictionary[string, string[]]]::new()
        if ($RetryAfter) { $Headers['Retry-After'] = @($RetryAfter) }
        [CIPP.CIPPHttpRequestException]::new('Service Unavailable', 503, $Headers, '<!DOCTYPE html><html><body>Sorry, something went wrong</body></html>')
    }
}

Describe 'New-GraphPOSTRequest 503 handling' {
    BeforeEach {
        $script:Calls = 0
        Mock Start-Sleep {}
        Mock Write-Warning {}
    }

    It 'retries a 503 and honours its Retry-After' {
        Mock Invoke-CIPPRestMethod {
            $script:Calls++
            if ($script:Calls -eq 1) { throw (New-BusyException '7') }
            'ok'
        }

        New-GraphPOSTRequest -uri 'https://contoso-admin.sharepoint.com/_vti_bin/client.svc/ProcessQuery' -tenantid 'contoso.onmicrosoft.com' -body '<Request />' | Should -Be 'ok'
        Should -Invoke Invoke-CIPPRestMethod -Times 2 -Exactly
        Should -Invoke Start-Sleep -ParameterFilter { $Seconds -eq 7 } -Times 1 -Exactly
    }

    It 'retries a 503 without Retry-After after a short back-off' {
        Mock Invoke-CIPPRestMethod {
            $script:Calls++
            if ($script:Calls -eq 1) { throw (New-BusyException $null) }
            'ok'
        }

        New-GraphPOSTRequest -uri 'https://contoso-admin.sharepoint.com/_vti_bin/client.svc/ProcessQuery' -tenantid 'contoso.onmicrosoft.com' -body '<Request />' | Should -Be 'ok'
        Should -Invoke Start-Sleep -ParameterFilter { $Seconds -lt 4 } -Times 1 -Exactly
    }
}
