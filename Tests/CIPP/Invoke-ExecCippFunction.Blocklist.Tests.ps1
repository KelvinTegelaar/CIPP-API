# The ExecCippFunction dispatcher must refuse every blocklisted function. The guard condition has to be
# parenthesised: without parentheses PowerShell parses it as one Get-Command call and the blocklist is
# never evaluated, so credential, certificate, token, Key Vault and managed-identity functions execute.

# Resolved at discovery time so the data-driven -ForEach below sees the real blocklist.
$script:FunctionPath = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Core/Invoke-ExecCippFunction.ps1'
$script:Source = Get-Content $script:FunctionPath -Raw
$script:BlockBody = [regex]::Match($script:Source, '\$BlockList = @\((?<body>.*?)\n    \)', 'Singleline').Groups['body'].Value
$script:BlockList = [regex]::Matches($script:BlockBody, "'(?<n>[^']+)'") | ForEach-Object { $_.Groups['n'].Value }

BeforeAll {
    $FunctionPath = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Core/Invoke-ExecCippFunction.ps1'

    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{} }

    # Stubs named after blocklisted functions. If the dispatcher ever invokes one, the test fails because
    # the response body would be this marker instead of the "not allowed" message.
    function Get-GraphToken { 'BLOCKED-FUNCTION-RAN' }
    function Get-CippKeyVaultSecret { 'BLOCKED-FUNCTION-RAN' }
    function Get-CIPPAzIdentityToken { 'BLOCKED-FUNCTION-RAN' }
    function Invoke-CIPPRestMethod { 'BLOCKED-FUNCTION-RAN' }
    function Get-CIPPTimerFunctions { 'ALLOWED-FUNCTION-RAN' }

    . $FunctionPath

    function New-Req { param($FunctionName) [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecCippFunction' }
            Headers = @{}
            Body    = @{ FunctionName = $FunctionName }
        } }
}

Describe 'Invoke-ExecCippFunction blocklist' {
    BeforeEach {
        # Report every candidate as a real CIPPCore function, so the only gate under test is the blocklist.
        Mock Get-Command -ParameterFilter { $Module -eq 'CIPPCore' } -MockWith { [pscustomobject]@{ Name = $Name } }
    }

    It 'has the credential, Key Vault, identity and arbitrary-HTTP functions on the blocklist' {
        $Src = Get-Content $FunctionPath -Raw
        foreach ($n in 'Get-GraphToken', 'Get-ClassicAPIToken', 'Get-CIPPSAMCertificate',
            'Get-CippKeyVaultSecret', 'Set-CippKeyVaultSecret', 'Remove-CippKeyVaultSecret',
            'Get-CIPPAzIdentityToken', 'New-CIPPAzRestRequest', 'Invoke-CIPPRestMethod') {
            $Src | Should -Match "'$([regex]::Escape($n))'" -Because "$n must never run through this dispatcher"
        }
    }

    It 'returns 404 and never invokes a blocklisted function: <_>' -ForEach $script:BlockList {
        $Response = Invoke-ExecCippFunction -Request (New-Req $_)
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::NotFound)
        $Response.Body | Should -Match 'not found or not allowed'
        $Response.Body | Should -Not -Be 'BLOCKED-FUNCTION-RAN'
    }

    It 'still runs a function that is not on the blocklist' {
        $Response = Invoke-ExecCippFunction -Request (New-Req 'Get-CIPPTimerFunctions')
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.Body | Should -Be 'ALLOWED-FUNCTION-RAN'
    }
}
