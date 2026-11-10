BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Baselines/Resolve-CIPPBaselineExpiry.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Settings/Invoke-ExecBaselineExpiryPolicy.ps1')
    function Get-CIPPBaselineExpiryPolicy { $script:Policy }
    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) $script:Saved = $Entity }
    function Write-LogMessage { param($headers, $API, $message, $Sev) }

    if (-not ('HttpStatusCode' -as [type])) {
        ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators'))::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }
    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Day = 86400
}

Describe 'Resolve-CIPPBaselineExpiry' {
    BeforeEach { $Now = [datetimeoffset]::UtcNow.ToUnixTimeSeconds() }

    It 'keeps the requested expiry, or none, when there is no maximum' {
        $script:Policy = [pscustomobject]@{ defaultDays = 365; maxDays = 0 }
        Resolve-CIPPBaselineExpiry -Expires '' | Should -BeNullOrEmpty
        Resolve-CIPPBaselineExpiry -Expires ($Now + 900 * $Day) | Should -Be ($Now + 900 * $Day)
    }

    It 'applies the default when no expiry is given and a maximum is set' {
        $script:Policy = [pscustomobject]@{ defaultDays = 30; maxDays = 365 }
        $Result = Resolve-CIPPBaselineExpiry -Expires $null
        $Result | Should -BeGreaterOrEqual ($Now + 30 * $Day)
        $Result | Should -BeLessThan ($Now + 30 * $Day + 60)
    }

    It 'falls back to the maximum when there is no default' {
        $script:Policy = [pscustomobject]@{ defaultDays = 0; maxDays = 90 }
        Resolve-CIPPBaselineExpiry -Expires '' | Should -BeGreaterOrEqual ($Now + 90 * $Day)
    }

    It 'refuses an expiry beyond the maximum and allows one within it' {
        $script:Policy = [pscustomobject]@{ defaultDays = 0; maxDays = 365 }
        { Resolve-CIPPBaselineExpiry -Expires ($Now + 400 * $Day) } | Should -Throw -ExceptionType ([System.ArgumentException])
        Resolve-CIPPBaselineExpiry -Expires ($Now + 365 * $Day) | Should -Be ($Now + 365 * $Day)
    }
}

Describe 'Invoke-ExecBaselineExpiryPolicy' {
    BeforeEach { $script:Saved = $null }

    It 'returns 400 for <Case>' -ForEach @(
        @{ Case = 'missing values'; Body = @{} }
        @{ Case = 'a negative value'; Body = @{ defaultDays = -1; maxDays = 0 } }
        @{ Case = 'a default longer than the maximum'; Body = @{ defaultDays = 400; maxDays = 365 } }
    ) {
        $Response = Invoke-ExecBaselineExpiryPolicy -Request ([pscustomobject]@{ Params = @{ CIPPEndpoint = 'x' }; Headers = @{}; Body = [pscustomobject]$Body })
        $Response.StatusCode | Should -Be 400
        $script:Saved | Should -BeNullOrEmpty
    }

    It 'saves a valid policy' {
        $Response = Invoke-ExecBaselineExpiryPolicy -Request ([pscustomobject]@{ Params = @{ CIPPEndpoint = 'x' }; Headers = @{}; Body = [pscustomobject]@{ defaultDays = '365'; maxDays = 0 } })
        $Response.StatusCode | Should -Be 200
        $script:Saved.defaultDays | Should -Be 365
        $script:Saved.maxDays | Should -Be 0
    }
}
