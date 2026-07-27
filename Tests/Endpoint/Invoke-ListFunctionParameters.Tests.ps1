# Pester tests for Invoke-ListFunctionParameters
# Validates the pregenerated cache path (Config/function-parameters.json), the guard
# that skips commands outside the pregenerated set (deployed legacy behavior), the
# live Get-Help fallback when no cache exists, and entrypoint filtering.

BeforeAll {
    # Resolve by name under Modules/ so the test survives the function moving between modules.
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListFunctionParameters.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ListFunctionParameters.ps1 under Modules/' }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    # The Functions worker exposes [HttpStatusCode]; map it for standalone test runs.
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function New-ExoRequest { param($AvailableCmdlets, $tenantid, $NoAuthCheck, $Compliance) }

    # fake FunctionInfo, endpoint reads Name / Visibility / Parameters
    function New-FakeFunction {
        param($Name)
        [pscustomobject]@{
            Name       = $Name
            Visibility = 'Public'
            Parameters = @{
                SomeParam = [pscustomobject]@{
                    ParameterType = [pscustomobject]@{ FullName = 'System.String' }
                    Attributes    = @([pscustomobject]@{ Mandatory = $true })
                }
            }
        }
    }

    function New-CacheFile {
        param($Root, $Functions)
        $configDir = Join-Path $Root 'Config'
        $null = New-Item -ItemType Directory -Path $configDir -Force
        $Functions | ConvertTo-Json -Depth 8 | Set-Content -Path (Join-Path $configDir 'function-parameters.json')
    }

    . $FunctionPath

    # the function also emits $Results to the pipeline before returning the
    # response context, the worker keys on the HttpResponseContext object
    function Invoke-Endpoint {
        param($Request)
        Invoke-ListFunctionParameters -Request $Request -TriggerMetadata $null | Where-Object { $_ -is [HttpResponseContext] } | Select-Object -First 1
    }
}

Describe 'Invoke-ListFunctionParameters' {
    BeforeEach {
        $global:CIPPFunctionParameters = $null
        $script:savedRootPath = $env:CIPPRootPath

        Mock -CommandName Get-Help -MockWith {
            [pscustomobject]@{
                Functionality = ''
                Synopsis      = 'live synopsis'
                parameters    = [pscustomobject]@{
                    parameter = @([pscustomobject]@{ name = 'SomeParam'; description = @([pscustomobject]@{ Text = 'live description' }) })
                }
            }
        }
    }

    AfterEach {
        $global:CIPPFunctionParameters = $null
        $env:CIPPRootPath = $script:savedRootPath
    }

    It 'serves cached functions without calling Get-Help' {
        $env:CIPPRootPath = Join-Path $TestDrive 'cached'
        New-CacheFile -Root $env:CIPPRootPath -Functions @{
            'Get-CIPPFoo' = @{
                Functionality = ''
                Synopsis      = 'cached synopsis'
                Parameters    = @(@{ Name = 'SomeParam'; Type = 'System.String'; Description = 'cached description'; Required = $true })
            }
        }
        Mock -CommandName Get-Command -MockWith { @(New-FakeFunction -Name 'Get-CIPPFoo') }

        $request = [pscustomobject]@{ Query = [pscustomobject]@{ Module = 'CIPPCore' } }
        $response = Invoke-Endpoint -Request $request

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $response.Body | Should -HaveCount 1
        $response.Body[0].Function | Should -Be 'Get-CIPPFoo'
        $response.Body[0].Synopsis | Should -Be 'cached synopsis'
        $response.Body[0].Parameters[0].Description | Should -Be 'cached description'
        Should -Invoke Get-Help -Times 0 -Exactly
    }

    It 'skips functions outside the pregenerated set without calling Get-Help' {
        $env:CIPPRootPath = Join-Path $TestDrive 'partial'
        New-CacheFile -Root $env:CIPPRootPath -Functions @{
            'Get-CIPPFoo' = @{
                Functionality = ''
                Synopsis      = 'cached synopsis'
                Parameters    = @(@{ Name = 'SomeParam'; Type = 'System.String'; Description = 'cached description'; Required = $true })
            }
        }
        # cache present -> uncached commands are guard-skipped, never Get-Help'd
        # (a bare Get-Command can return every command in the runspace)
        Mock -CommandName Get-Command -MockWith {
            @((New-FakeFunction -Name 'Get-CIPPFoo'), (New-FakeFunction -Name 'Get-SomeOtherModuleThing'))
        }

        $request = [pscustomobject]@{ Query = [pscustomobject]@{ Module = 'CIPPCore' } }
        $response = Invoke-Endpoint -Request $request

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $response.Body | Should -HaveCount 1
        $response.Body[0].Function | Should -Be 'Get-CIPPFoo'
        Should -Invoke Get-Help -Times 0 -Exactly
    }

    It 'uses live Get-Help for everything when no cache file exists' {
        $env:CIPPRootPath = Join-Path $TestDrive 'empty'
        $null = New-Item -ItemType Directory -Path $env:CIPPRootPath -Force
        Mock -CommandName Get-Command -MockWith {
            @((New-FakeFunction -Name 'Get-CIPPFoo'), (New-FakeFunction -Name 'Get-CIPPBar'))
        }

        $request = [pscustomobject]@{ Query = [pscustomobject]@{ Module = 'CIPPCore' } }
        $response = Invoke-Endpoint -Request $request

        $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $response.Body | Should -HaveCount 2
        Should -Invoke Get-Help -Times 2 -Exactly
    }

    It 'filters out entrypoint functions listed in the cache' {
        $env:CIPPRootPath = Join-Path $TestDrive 'entrypoints'
        New-CacheFile -Root $env:CIPPRootPath -Functions @{
            'Get-CIPPFoo'    = @{
                Functionality = ''
                Synopsis      = 'cached synopsis'
                Parameters    = @()
            }
            'Invoke-CIPPBar' = @{
                Functionality = 'Entrypoint,AnyTenant'
                Synopsis      = 'an entrypoint'
                Parameters    = @()
            }
        }
        Mock -CommandName Get-Command -MockWith {
            @((New-FakeFunction -Name 'Get-CIPPFoo'), (New-FakeFunction -Name 'Invoke-CIPPBar'))
        }

        $request = [pscustomobject]@{ Query = [pscustomobject]@{ Module = 'CIPPCore' } }
        $response = Invoke-Endpoint -Request $request

        $response.Body | Should -HaveCount 1
        $response.Body[0].Function | Should -Be 'Get-CIPPFoo'
    }
}
