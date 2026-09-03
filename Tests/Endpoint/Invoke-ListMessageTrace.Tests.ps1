# Pester tests for Invoke-ListMessageTrace
# Regression coverage for the "days" window off-by-epsilon: two separate Get-Date/UtcNow
# calls for Start/End made a "last 10 days" search span slightly over 10 days and trip the
# 10-day-window guard. Also covers that an explicit range genuinely over 10 days is still rejected.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    # Stub every CIPP helper the function calls so Pester's Mock has a command to replace.
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, $NoAuthCheck) }
    function New-GraphPostRequest { param($Uri, $tenantid, $type, $body, $NoAuthCheck) }
    function New-ExoRequest { param($TenantId, $Cmdlet, $CmdParams) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev) }
    function Get-NormalizedError { param($message) $message }

    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Email-Exchange/Tools/Invoke-ListMessageTrace.ps1'
    $EndpointScript = [ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw))
    . $EndpointScript

    function New-MessageTraceRequest {
        param([hashtable]$Body = @{})
        $Merged = @{ tenantFilter = 'contoso.onmicrosoft.com' }
        foreach ($Key in $Body.Keys) { $Merged[$Key] = $Body[$Key] }
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListMessageTrace' }
            Headers = @{ Authorization = 'token' }
            Body    = [pscustomobject]$Merged
        }
    }
}

Describe 'Invoke-ListMessageTrace date window validation' {
    BeforeEach {
        Mock -CommandName New-GraphGetRequest -MockWith {
            @([pscustomobject]@{ id = 'trace1'; messageId = 'msg1'; status = 'delivered'; subject = 'hi'; recipientAddress = 'to@contoso.com'; senderAddress = 'from@contoso.com'; receivedDateTime = (Get-Date).ToUniversalTime().ToString('o'); size = 100; fromIP = '1.1.1.1'; toIP = '2.2.2.2' })
        }
        Mock -CommandName New-GraphPostRequest -MockWith { }
        Mock -CommandName New-ExoRequest -MockWith { throw 'live EXO should not be called' }
        Mock -CommandName Write-LogMessage -MockWith { }
    }

    It 'does not reject a "last 10 days" relative search' {
        $response = Invoke-ListMessageTrace -Request (New-MessageTraceRequest -Body @{ days = 10 }) -TriggerMetadata $null

        $response.StatusCode | Should -Be 200
        $response.Body.Metadata.Error | Should -BeNullOrEmpty
        $response.Body.Results | Should -HaveCount 1
    }

    It 'rejects an explicit range spanning 10 days and 60 seconds' {
        $End = [DateTimeOffset]::UtcNow
        $Start = $End.AddDays(-10).AddSeconds(-60)

        $response = Invoke-ListMessageTrace -Request (New-MessageTraceRequest -Body @{
                startDate = $Start.ToUnixTimeSeconds().ToString()
                endDate   = $End.ToUnixTimeSeconds().ToString()
            }) -TriggerMetadata $null

        $response.StatusCode | Should -Be 500
        $response.Body.Metadata.Error | Should -Match '10 day window'
    }
}
