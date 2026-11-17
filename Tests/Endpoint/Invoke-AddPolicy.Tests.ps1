# Pester tests for Invoke-AddPolicy
# Per-tenant placeholder values from the deploy drawer

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-AddPolicy.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-AddPolicy.ps1 under Modules/' }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-CippTable { param($tablename) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter) $script:TemplateRow }
    function Repair-CIPPIntuneTemplateNesting { param($Template, $Table) $Template }
    function Get-CIPPReusableSettingsFromPolicy { param($PolicyJson, $Tenant, $Headers, $APIName) }
    function Test-CIPPIntuneTemplate { param($RawJSON, $TemplateType, $DisplayName) [pscustomobject]@{ IsValid = $true; Type = 'Device' } }
    function Set-CIPPIntunePolicy { param($TemplateType, $Description, $DisplayName, $RawJSON, $ReusableSettings, $AssignTo, $ExcludeGroup, $tenantFilter, $Headers, $APIName) $script:Deployed[$tenantFilter] = $RawJSON }
    function Get-CippBulkStatusCode { param($Total, $Failed) 200 }
    function Get-Tenants { }

    . $FunctionPath
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')

    function New-DeployRequest {
        param($ReplaceMap, $RawJSON = '{"description":"stale %sitecode%"}')
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'AddPolicy' }
            Headers = @{}
            Body    = [pscustomobject]@{
                tenantFilter = @([pscustomobject]@{ value = 'a.onmicrosoft.com' }, [pscustomobject]@{ value = 'b.onmicrosoft.com' })
                TemplateList = [pscustomobject]@{ value = 'template-guid' }
                displayName  = 'Probe'
                TemplateType = 'Device'
                RAWJson      = $RawJSON
                replacemap   = $ReplaceMap
            }
        }
    }
}

Describe 'Invoke-AddPolicy per-tenant placeholders' {
    BeforeEach {
        $script:Deployed = @{}
        $script:TemplateRow = [pscustomobject]@{
            JSON = (@{ RAWJson = '{"description":"site %sitecode%","pattern":"%s.tecode%"}' } | ConvertTo-Json -Compress)
        }
    }

    It 'gives each tenant its own value in the selected template' {
        $Response = Invoke-AddPolicy -Request (New-DeployRequest ([pscustomobject]@{
                    'a.onmicrosoft.com' = [pscustomobject]@{ '%sitecode%' = 'AAA' }
                    'b.onmicrosoft.com' = [pscustomobject]@{ '%sitecode%' = 'BBB' }
                }))

        $Response.StatusCode | Should -Be 200
        ($script:Deployed['a.onmicrosoft.com'] | ConvertFrom-Json).description | Should -Be 'site AAA'
        ($script:Deployed['b.onmicrosoft.com'] | ConvertFrom-Json).description | Should -Be 'site BBB'
    }

    It 'writes a value as literal, JSON-escaped text and matches the placeholder exactly' {
        $null = Invoke-AddPolicy -Request (New-DeployRequest ([pscustomobject]@{
                    'a.onmicrosoft.com' = [pscustomobject]@{ '%sitecode%' = 'say "hi" $1' }
                    'b.onmicrosoft.com' = [pscustomobject]@{ '%s.tecode%' = 'REGEX' }
                }))

        ($script:Deployed['a.onmicrosoft.com'] | ConvertFrom-Json).description | Should -Be 'site say "hi" $1'
        $PolicyB = $script:Deployed['b.onmicrosoft.com'] | ConvertFrom-Json
        $PolicyB.description | Should -Be 'site %sitecode%'
        $PolicyB.pattern | Should -Be 'REGEX'
    }
}
