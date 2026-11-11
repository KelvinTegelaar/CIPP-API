BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext { [object]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) { $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function New-CIPPCATemplate { param($TenantFilter, $JSON) }
    function Get-CippTable { param($tablename) @{ Context = 'templates' } }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, $Force) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }
    . (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Conditional/Invoke-AddCATemplate.ps1')

    function Invoke-Capture([hashtable]$SessionControls) {
        $Body = [pscustomobject]@{ tenantFilter = 'contoso.com'; displayName = 'Staff web filtering'; name = 'Staff web filtering'; sessionControls = $SessionControls }
        Invoke-AddCATemplate -Request ([pscustomobject]@{ Params = @{ CIPPEndpoint = 'AddCATemplate' }; Body = $Body })
    }
}

Describe 'Invoke-AddCATemplate' {
    BeforeEach {
        Mock New-CIPPCATemplate { '{"displayName":"Staff web filtering"}' }
        Mock Add-CIPPAzDataTableEntity {}
    }

    It 'stores the converted policy and reports the new template' {
        $Response = Invoke-Capture $null
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.Body.Results | Should -Match "^Created CA Template Staff web filtering with GUID [0-9a-f-]{36}$"
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Entity.PartitionKey -eq 'CATemplate' -and $Entity.JSON -eq '{"displayName":"Staff web filtering"}' }
    }

    It 'warns that the security profile is referred to by name and can be saved as a template separately' {
        Mock New-CIPPCATemplate { '{"displayName":"Staff web filtering","sessionControls":{"globalSecureAccessFilteringProfile":{"profileId":"Staff","isEnabled":true}}}' }
        $Response = Invoke-Capture $null
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        @($Response.Body.Results.state) | Should -Be @('success', 'warning')
        $Response.Body.Results[0].resultText | Should -Match '^Created CA Template Staff web filtering with GUID'
        $Response.Body.Results[1].resultText | Should -BeLike "*security profile 'Staff'. The CA template refers to it by name*Save as Template*"
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1
    }

    It 'reports a failed conversion as an error and stores nothing' {
        Mock New-CIPPCATemplate { throw 'Graph said no' }
        $Response = Invoke-Capture $null
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        $Response.Body.Results | Should -Be 'Failed to create CA Template: Graph said no'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0
    }
}
