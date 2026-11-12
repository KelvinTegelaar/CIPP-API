BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    foreach ($Name in 'Get-CippCustomScriptAllowedCommand', 'New-CippSandboxInitialSessionState', 'Invoke-CippSandboxScript') {
        . (Join-Path $RepoRoot "Modules/CIPPCore/Public/$Name.ps1")
    }

    $env:CIPP_SANDBOX_TEST_MARKER = 'marker-visible'
    $MarkerDir = Join-Path ([System.IO.Path]::GetTempPath()) ('cipp-sandbox-' + [guid]::NewGuid())
    $null = New-Item -ItemType Directory -Path $MarkerDir
    $MarkerFile = Join-Path $MarkerDir 'marker.txt'
    $MarkerScript = Join-Path $MarkerDir 'marker.ps1'
    Set-Content -Path $MarkerFile -Value 'file-visible'
    Set-Content -Path $MarkerScript -Value "Get-Content -LiteralPath '$MarkerFile'"
    $ExternalProgram = if ($IsWindows) { 'whoami.exe' } else { '/bin/echo' }

    function Invoke-Sandbox([string]$Code, [hashtable]$Data = @{}, [hashtable]$Params = @{}) {
        Invoke-CippSandboxScript -ScriptContent $Code -SandboxData $Data -ScriptParameters $Params -TimeoutSeconds 30
    }

    function Get-SandboxOutputText([string]$Code) {
        (@((Invoke-Sandbox $Code).Output) | Where-Object { $null -ne $_ } | ForEach-Object { "$_" }) -join ','
    }
}

AfterAll {
    Remove-Item -Path $MarkerDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path Env:CIPP_SANDBOX_TEST_MARKER -ErrorAction SilentlyContinue
}

Describe 'Custom test sandbox: commands outside the allowlist' {
    It 'a <Context> cannot call a command outside the allowlist' -ForEach @(
        @{ Context = 'top-level statement'; Wrap = '{0}' }
        @{ Context = 'function defined by the script'; Wrap = "function Probe {{ {0} }}`nProbe" }
        @{ Context = 'script block'; Wrap = "`$sb = {{ {0} }}`n& `$sb" }
        @{ Context = 'ForEach-Object script block'; Wrap = '1 | ForEach-Object {{ {0} }}' }
        @{ Context = 'calculated property'; Wrap = "(1 | Select-Object @{{ Name = 'x'; Expression = {{ {0} }} }}).x" }
    ) {
        $Probe = "Get-Content -LiteralPath '$MarkerFile'"
        Get-SandboxOutputText ($Wrap -f $Probe) | Should -Not -Match 'file-visible'
    }

    It 'a command name held in a string cannot reach a command outside the allowlist' {
        Get-SandboxOutputText "`$sb = { `$c = 'Get-Content'; & `$c -LiteralPath '$MarkerFile' }; & `$sb" | Should -Not -Match 'file-visible'
    }

    It 'the session contains only allowlisted commands and their aliases' {
        $Allowed = Get-CippCustomScriptAllowedCommand
        $Iss = New-CippSandboxInitialSessionState
        $Unexpected = @($Iss.Commands | Where-Object {
                $Name = if ($_ -is [System.Management.Automation.Runspaces.SessionStateAliasEntry]) { $_.Definition } else { $_.Name }
                $Name -notin $Allowed
            } | ForEach-Object Name)
        $Unexpected | Should -BeNullOrEmpty
        $Iss.Providers.Count | Should -Be 0
    }
}

Describe 'Custom test sandbox: host access' {
    It 'cannot start an external program from a script block' {
        Get-SandboxOutputText "`$sb = { & '$ExternalProgram' 'program-ran' }; & `$sb" | Should -BeNullOrEmpty
    }

    It 'a script file reached from a script block gets no commands outside the allowlist' {
        Get-SandboxOutputText "`$sb = { . '$MarkerScript' }; & `$sb" | Should -Not -Match 'file-visible'
    }

    It 'cannot read the process environment through <Name>' -ForEach @(
        @{ Name = 'an env variable'; Code = '$env:CIPP_SANDBOX_TEST_MARKER' }
        @{ Name = 'the Env drive'; Code = '$sb = { (Get-Item Env:CIPP_SANDBOX_TEST_MARKER).Value }; & $sb' }
    ) {
        Get-SandboxOutputText $Code | Should -Not -Match 'marker-visible'
    }

    It 'an allowed command cannot read a file by path' {
        Get-SandboxOutputText "(Select-String -Path '$MarkerFile' -Pattern 'file').Line" | Should -Not -Match 'file-visible'
    }

    It 'cannot load a command from an installed module' {
        Get-SandboxOutputText '$sb = { ConvertTo-SecureString -String x -AsPlainText -Force | ForEach-Object { "module-loaded" } }; & $sb' | Should -Not -Match 'module-loaded'
    }

    It 'cannot call .NET static methods' {
        Get-SandboxOutputText "[System.IO.File]::ReadAllText('$MarkerFile')" | Should -Not -Match 'file-visible'
    }
}

Describe 'Custom test sandbox: legitimate scripts' {
    It 'runs every allowlisted command, aliases and script-defined helpers' {
        $Code = @'
param($Threshold = 2)
function Get-Big($Items) { $Items | Where-Object { $_ -gt $Threshold } }
$Rows = Get-CIPPTestData -Type 'Users'
$Json = $Rows | ConvertTo-Json -Depth 3 | ConvertFrom-Json
$Grouped = $Json | Group-Object -Property dept | Sort-Object -Property Name
$Sum = ($Json | Measure-Object -Property n -Sum).Sum
$Diff = @(Compare-Object -ReferenceObject @(1, 2) -DifferenceObject @(2, 3)).Count
$Unique = @(1, 1, 2 | Get-Unique).Count
$Members = @($Json[0] | Get-Member -MemberType NoteProperty).Count
$Match = ('alpha', 'beta' | Select-String -Pattern 'bet').Line
$Span = (New-TimeSpan -Days 1).TotalHours
$Guid = (New-Guid).Guid.Length
$Rand = Get-Random -Minimum 5 -Maximum 6
$Year = (Get-Date).Year -gt 2000
$Calc = $Json | Select-Object @{ Name = 'Upper'; Expression = { ($_.dept | % { $_.ToUpper() }) } }
Write-Output @{
    Groups = ($Grouped | ForEach-Object Name) -join '|'
    Sum = $Sum; Diff = $Diff; Unique = $Unique; Members = $Members; Match = $Match
    Span = $Span; Guid = $Guid; Rand = $Rand; Year = $Year
    Big = @(Get-Big -Items $Json.n).Count
    Upper = ($Calc.Upper -join '|')
}
'@
        $Data = @{ Users = @(@{ dept = 'b'; n = 1 }, @{ dept = 'a'; n = 3 }, @{ dept = 'a'; n = 5 }) }
        $Run = Invoke-Sandbox -Code $Code -Data $Data -Params @{ TenantFilter = 't' }
        $Run.HadErrors | Should -BeFalse -Because (@($Run.Errors) -join '; ')
        $Out = $Run.Output[0]
        $Out.Groups | Should -Be 'a|b'
        $Out.Sum | Should -Be 9
        $Out.Diff | Should -Be 2
        $Out.Unique | Should -Be 2
        $Out.Members | Should -Be 2
        $Out.Match | Should -Be 'beta'
        $Out.Span | Should -Be 24
        $Out.Guid | Should -Be 36
        $Out.Rand | Should -Be 5
        $Out.Year | Should -BeTrue
        $Out.Big | Should -Be 2
        $Out.Upper | Should -Be 'B|A|A'
    }

    It 'runs the example scripts shown on the custom test page' {
        $Page = Join-Path (Split-Path -Parent $RepoRoot) 'frontend/src/pages/tools/custom-tests/add.jsx'
        if (-not (Test-Path $Page)) { Set-ItResult -Skipped -Because 'the frontend source is not present'; return }
        $Examples = @([regex]::Matches((Get-Content -Raw $Page), '(?s)code=\{`(.*?)`\}') | ForEach-Object { $_.Groups[1].Value })
        $Examples.Count | Should -BeGreaterThan 0
        # Cache rows reach the sandbox as deserialised JSON objects.
        $Data = @{}
        @{
            Users                     = @{ userPrincipalName = 'u@x'; displayName = 'U'; accountEnabled = $false; assignedLicenses = @(@{ skuId = 's1' }) }
            LicenseOverview           = @{ skuId = 's1'; License = 'E5' }
            UserRegistrationDetails   = @{ userPrincipalName = 'u@x'; userDisplayName = 'U'; isAdmin = $false; userType = 'member'; methodsRegistered = @() }
            Guests                    = @{ userPrincipalName = 'g@x'; displayName = 'G'; createdDateTime = '2020-01-01'; signInActivity = @{ lastSignInDateTime = '2020-01-01' } }
            ConditionalAccessPolicies = @{ displayName = 'P'; state = 'enabled'; createdDateTime = '2020-01-01' }
        }.GetEnumerator() | ForEach-Object { $Data[$_.Key] = @($_.Value | ConvertTo-Json -Depth 5 | ConvertFrom-Json) }
        foreach ($Example in $Examples) {
            $Run = Invoke-Sandbox -Code $Example -Data $Data -Params @{ TenantFilter = 't' }
            $Run.HadErrors | Should -BeFalse -Because (@($Run.Errors) -join '; ')
            @($Run.Output | Where-Object { $null -ne $_ }).Count | Should -BeGreaterThan 0
        }
    }
}
