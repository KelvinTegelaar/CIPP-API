# The Test button for the CyberDrain Managed Baselines extension.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }

    function Get-CIPPTable { param($TableName) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter) [pscustomobject]@{ config = '{"CyberDrainManagedBaselines":{"Enabled":true}}' } }
    function Invoke-ManagedBaselinesRequest { param($Path, $Method, $Body) }
    . (Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Extensions/Invoke-ExecExtensionTest.ps1')

    $script:Request = [pscustomobject]@{ Query = [pscustomobject]@{ extensionName = 'CyberDrainManagedBaselines' } }
}

Describe 'Invoke-ExecExtensionTest for CyberDrain Managed Baselines' {
    It 'names the partner the key belongs to' {
        Mock Invoke-ManagedBaselinesRequest { [pscustomobject]@{ partnerName = 'Contoso MSP'; plan = 'Standard' } }

        $Response = Invoke-ExecExtensionTest -Request $script:Request

        $Response.StatusCode | Should -Be 200
        $Response.Body.Results | Should -BeLike '*Contoso MSP*'
        Should -Invoke Invoke-ManagedBaselinesRequest -Times 1 -Exactly -ParameterFilter { $Path -eq 'account' }
    }

    It 'answers with an error status and the reason when CyberDrain refuses the key' {
        Mock Invoke-ManagedBaselinesRequest { throw [System.UnauthorizedAccessException]::new('CyberDrain rejected the API key. Check the key under Integrations.') }

        $Response = Invoke-ExecExtensionTest -Request $script:Request

        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -BeLike '*rejected the API key*'
    }
}
