BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext { [object]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) { $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function New-CIPPCATemplate { param($TenantFilter, $JSON) }
    function Get-CippTable { param($tablename) @{ Context = 'templates' } }
    function Add-CIPPAzDataTableEntity { [CmdletBinding()] param($Context, $Entity, [switch]$Force) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }
    function Get-CIPPAzDataTableEntity { [CmdletBinding()] param($Context, $Filter) $script:Stored }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Merge-CIPPTemplateVariable.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Conditional/Invoke-AddCATemplate.ps1')

    function Invoke-Capture([hashtable]$SessionControls, [hashtable]$Options = @{}) {
        $Body = [pscustomobject](@{ tenantFilter = 'contoso.com'; displayName = 'Staff web filtering'; name = 'Staff web filtering'; sessionControls = $SessionControls } + $Options)
        Invoke-AddCATemplate -Request ([pscustomobject]@{ Params = @{ CIPPEndpoint = 'AddCATemplate' }; Body = $Body })
    }
}

Describe 'Invoke-AddCATemplate' {
    BeforeEach {
        Mock New-CIPPCATemplate { '{"displayName":"Staff web filtering"}' }
        Mock Add-CIPPAzDataTableEntity {}
        $script:Stored = @()
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

    Context 'replacing the template with the same name' {
        BeforeEach {
            Mock New-CIPPCATemplate { '{"displayName":"Staff web filtering","state":"enabled","conditions":{"users":{"excludeUsers":["bg1@contoso.com"]}}}' }
            $script:Stored = @(
                [pscustomobject]@{ RowKey = 'existing-guid'; Package = 'Baseline'; JSON = '{"displayName":"Staff web filtering","state":"disabled","conditions":{"users":{"excludeUsers":["%breakglass%"]}}}' }
                [pscustomobject]@{ RowKey = 'other-guid'; JSON = '{"displayName":"Something else"}' }
            )
        }

        It 'updates the existing template in place and keeps its variables' {
            $Response = Invoke-Capture $null @{ ReplaceExisting = $true; KeepVariables = $true }
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            $Response.Body.Results | Should -Be 'Updated CA Template Staff web filtering with GUID existing-guid'
            Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter {
                $Entity.RowKey -eq 'existing-guid' -and $Entity.GUID -eq 'existing-guid' -and $Entity.Package -eq 'Baseline' -and
                $Entity.JSON -eq '{"displayName":"Staff web filtering","state":"enabled","conditions":{"users":{"excludeUsers":["%breakglass%"]}}}'
            }
            Should -Invoke New-CIPPCATemplate -Times 1 -ParameterFilter { -not $JSON.PSObject.Properties['ReplaceExisting'] -and -not $JSON.PSObject.Properties['KeepVariables'] }
        }

        It 'takes the captured policy whole without KeepVariables' {
            $null = Invoke-Capture $null @{ ReplaceExisting = $true }
            Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Entity.RowKey -eq 'existing-guid' -and $Entity.JSON -like '*bg1@contoso.com*' }
        }

        It 'adds a new template when none has the name' {
            $script:Stored = @([pscustomobject]@{ RowKey = 'other-guid'; JSON = '{"displayName":"Something else"}' })
            $Response = Invoke-Capture $null @{ ReplaceExisting = $true; KeepVariables = $true }
            $Response.Body.Results | Should -Match '^Created CA Template'
            Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Entity.RowKey -ne 'other-guid' }
        }

        It 'refuses when two templates share the name' {
            $script:Stored += [pscustomobject]@{ RowKey = 'dupe-guid'; JSON = '{"displayName":"Staff web filtering"}' }
            $Response = Invoke-Capture $null @{ ReplaceExisting = $true }
            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0
        }

        It 'warns about variables on settings the policy no longer has' {
            Mock New-CIPPCATemplate { '{"displayName":"Staff web filtering","conditions":{}}' }
            $Response = Invoke-Capture $null @{ ReplaceExisting = $true; KeepVariables = $true }
            $Response.Body.Results[1].state | Should -Be 'warning'
            $Response.Body.Results[1].resultText | Should -BeLike '*no longer has*%breakglass%'
        }
    }
}
