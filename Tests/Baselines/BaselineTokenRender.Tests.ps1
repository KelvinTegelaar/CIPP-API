# Token substitution must only ever produce VALUES. A variable or read-record value is user or
# tenant data; if it could close a JSON string it could add or override method, uri, body or
# cmdlet keys of a write that runs with CIPP's identity. These drive the real engine render and
# the real executors with values that would break out of a serialized template.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public'

    function New-GraphBulkRequest { param($tenantid, $scope, $asapp, $Requests, $Version, $Headers, $NoAuthCheck, $NoPaginateIds) }
    function New-ExoBulkRequest { param($tenantid, $cmdletArray, $useSystemMailbox, [int]$MaxConcurrency = 1, [switch]$Compliance) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $useSystemMailbox, [switch]$Compliance) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }

    . (Join-Path $Baselines 'Helpers/Get-CIPPBaselineCommand.ps1')
    . (Join-Path $Baselines 'Helpers/Expand-CIPPBaselineToken.ps1')
    . (Join-Path $Baselines 'Executors/Invoke-CIPPBaselineGraphBulkSweep.ps1')
    . (Join-Path $Baselines 'Executors/Invoke-CIPPBaselineExoBulkSweep.ps1')
    . (Join-Path $Baselines 'Executors/Invoke-CIPPBaselineExoRequest.ps1')

    # The engine's own $Render, lifted out of Invoke-CIPPBaselineStandard so the test runs it verbatim.
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Baselines 'Helpers/Invoke-CIPPBaselineStandard.ps1'), [ref]$null, [ref]$null)
    $Assign = $Ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$Render' }, $true)
    $script:Render = [scriptblock]::Create($Assign.Right.Expression.Extent.Text.Trim('{', '}'))
    function Invoke-Render { param($Definition, $Template, $Variables) $TenantFilter = 'contoso.onmicrosoft.com'; & $script:Render $Template $Variables }

    function Get-Definition { param($Path) Get-Content -Raw (Join-Path $script:RepoRoot "Config/BaselineStandards/$Path") | ConvertFrom-Json }
    function ConvertTo-Spec { param([Parameter(ValueFromPipeline = $true)]$InputObject) process { $InputObject | ConvertTo-Json -Depth 20 | ConvertFrom-Json } }

    $script:Tricky = "He said ""hi"" C:\temp\new`nline2`ttab caf$([char]0xE9) $([char]0x65E5)"
    $script:Breakout = 'x","method":"POST","asApp":true,"uri":"servicePrincipals/0000'
    $script:Synthetic = @{
        variables = @{
            n    = @{ type = 'number' }
            b    = @{ type = 'switch' }
            arr  = @{ type = 'autoComplete'; multiple = $true }
            obj  = @{ type = 'textField' }
            s    = @{ type = 'textField' }
            gone = @{ type = 'textField'; omitWhenBlank = $true }
        }
    } | ConvertTo-Spec
}

Describe 'Engine render' {
    Context 'a value can never change the instruction structure' {
        It 'keeps a declared embedded value inside its own string' {
            $Template = @{ requests = @(@{ method = 'PATCH'; uri = 'users/%s%'; asApp = $false; body = @{ a = 1 } }) } | ConvertTo-Spec
            $Out = Invoke-Render -Definition $script:Synthetic -Template $Template -Variables ([PSCustomObject]@{ s = $script:Breakout })
            $Out.requests[0].method | Should -Be 'PATCH'
            $Out.requests[0].asApp | Should -BeFalse
            $Out.requests[0].uri | Should -BeExactly "users/$script:Breakout"
            @($Out.requests[0].PSObject.Properties.Name | Sort-Object) | Should -Be @('asApp', 'body', 'method', 'uri')
        }

        It 'does not let an undeclared variable rewrite DisableGuests writes' {
            $Definition = Get-Definition 'Entra (AAD) Standards/DisableGuests.json'
            $Out = Invoke-Render -Definition $Definition -Template $Definition.remediate -Variables ([PSCustomObject]@{ days = 90; id = $script:Breakout })
            (ConvertTo-Json -Compress -Depth 20 $Out) | Should -BeExactly (ConvertTo-Json -Compress -Depth 20 $Definition.remediate)
        }

        It 'leaves a read-record token for the executor even when a variable shares its name' {
            $Definition = Get-Definition 'Entra (AAD) Standards/DisableGuests.json'
            $Out = Invoke-Render -Definition $Definition -Template $Definition.remediate -Variables ([PSCustomObject]@{ days = 90; id = '00000000-0000-0000-0000-000000000001' })
            @($Out.writes.uri) | Should -Be @('users/%id%', 'users/%id%')
        }
    }

    Context 'legitimate values render as before' {
        It 'keeps whole-value tokens typed' {
            $Template = @{ n = '%n%'; b = '%b%'; arr = '%arr%'; obj = '%obj%' } | ConvertTo-Spec
            $Variables = [PSCustomObject]@{
                n   = '30'
                b   = $true
                arr = @([PSCustomObject]@{ label = 'One'; value = 'one' })
                obj = [PSCustomObject]@{ k = 'v'; inner = @(1, 2) }
            }
            $Out = Invoke-Render -Definition $script:Synthetic -Template $Template -Variables $Variables
            $Out.n | Should -BeOfType ([long])
            $Out.n | Should -Be 30
            $Out.b | Should -BeOfType ([bool])
            , $Out.arr | Should -BeOfType ([array])
            @($Out.arr) | Should -Be @('one')
            $Out.obj.k | Should -Be 'v'
            @($Out.obj.inner) | Should -Be @(1, 2)
        }

        It 'renders quotes, backslashes, newlines and non-ASCII exactly, whole and embedded' {
            $Template = @{ whole = '%s%'; embedded = 'pre-%s%-post'; list = @('%s%', 'x %s%') } | ConvertTo-Spec
            $Out = Invoke-Render -Definition $script:Synthetic -Template $Template -Variables ([PSCustomObject]@{ s = $script:Tricky })
            $Out.whole | Should -BeExactly $script:Tricky
            $Out.embedded | Should -BeExactly "pre-$script:Tricky-post"
            $Out.list[0] | Should -BeExactly $script:Tricky
            $Out.list[1] | Should -BeExactly "x $script:Tricky"
        }

        It 'drops an omitWhenBlank key at any depth and keeps the rest' {
            $Template = @{ keep = 1; gone = '%gone%'; nested = @{ gone = '%gone%'; other = 'y' }; rows = @(@{ gone = '%gone%'; z = 2 }) } | ConvertTo-Spec
            $Out = Invoke-Render -Definition $script:Synthetic -Template $Template -Variables ([PSCustomObject]@{ gone = '' })
            @($Out.PSObject.Properties.Name) | Should -Not -Contain 'gone'
            @($Out.nested.PSObject.Properties.Name) | Should -Be @('other')
            @($Out.rows[0].PSObject.Properties.Name) | Should -Be @('z')
            $Out.keep | Should -Be 1
        }

        It 'still fills a legacy undeclared whole-value token' {
            # AutopilotProfile baselines saved before AssignTo carry only AssignToAllDevices.
            $Definition = Get-Definition 'Intune Standards/AutopilotProfile.json'
            $Out = Invoke-Render -Definition $Definition -Template $Definition.remediate -Variables ([PSCustomObject]@{ AssignToAllDevices = $true })
            $Out.assignToAllDevices | Should -BeTrue
        }

        It 'does not mutate the definition it renders' {
            $Definition = Get-Definition 'Entra (AAD) Standards/DisableGuests.json'
            $Before = ConvertTo-Json -Compress -Depth 20 $Definition
            $null = Invoke-Render -Definition $Definition -Template $Definition.expected -Variables ([PSCustomObject]@{ days = '30' })
            ConvertTo-Json -Compress -Depth 20 $Definition | Should -BeExactly $Before
        }
    }
}

Describe 'Executor token expansion' {
    BeforeEach {
        Mock New-GraphBulkRequest { @($Requests | ForEach-Object { [PSCustomObject]@{ id = $_.id; status = 204 } }) }
        Mock New-ExoBulkRequest { @($cmdletArray | ForEach-Object { [PSCustomObject]@{ Success = $true; OperationGuid = $_.OperationGuid } }) }
        Mock New-ExoRequest {}
        Mock Write-LogMessage {}
    }

    It 'GraphBulkSweep keeps a record value inside the url and body strings' {
        $Current = [PSCustomObject]@{ targets = @([PSCustomObject]@{ id = $script:Breakout; name = $script:Tricky; rule = [PSCustomObject]@{ a = 1 } }) }
        $Spec = @{ writes = @(@{ method = 'PATCH'; uri = 'users/%id%'; body = @{ note = 'for %name%'; whole = '%name%'; rule = '%rule%' } }) } | ConvertTo-Spec
        Invoke-CIPPBaselineGraphBulkSweep -Remediate $Spec -TenantFilter 'contoso.onmicrosoft.com' -Current $Current
        Should -Invoke New-GraphBulkRequest -Times 1 -ParameterFilter {
            $R = @($Requests)[0]
            $R.method -eq 'PATCH' -and $R.url -ceq "/users/$script:Breakout" -and
            $R.body.note -ceq "for $script:Tricky" -and $R.body.whole -ceq $script:Tricky -and $R.body.rule.a -eq 1 -and
            @($R.body.PSObject.Properties.Name).Count -eq 3
        }
    }

    It 'ExoBulkSweep keeps a record value inside its parameter' {
        $Current = [PSCustomObject]@{ targets = @([PSCustomObject]@{ id = $script:Breakout }) }
        $Spec = @{ writes = @(@{ cmdlet = 'Set-Mailbox'; params = @{ Identity = '%id%'; CustomAttribute1 = 'tag %id%' } }) } | ConvertTo-Spec
        Invoke-CIPPBaselineExoBulkSweep -Remediate $Spec -TenantFilter 'contoso.onmicrosoft.com' -Current $Current
        Should -Invoke New-ExoBulkRequest -Times 1 -ParameterFilter {
            $P = @($cmdletArray)[0].CmdletInput.Parameters
            @($cmdletArray)[0].CmdletInput.CmdletName -eq 'Set-Mailbox' -and $P.Keys.Count -eq 2 -and
            $P['Identity'] -ceq $script:Breakout -and $P['CustomAttribute1'] -ceq "tag $script:Breakout"
        }
    }

    It 'ExoRequest keeps a read-record value inside its parameter' {
        $Current = [PSCustomObject]@{ Name = $script:Tricky + '","Remove":"' }
        $Spec = @{ cmdlets = @(@{ cmdlet = 'Set-TeamsProtectionPolicy'; params = @{ Identity = '%Name%'; Comment = 'policy %Name%' } }) } | ConvertTo-Spec
        Invoke-CIPPBaselineExoRequest -Remediate $Spec -TenantFilter 'contoso.onmicrosoft.com' -Current $Current
        Should -Invoke New-ExoRequest -Times 1 -ParameterFilter {
            $cmdlet -eq 'Set-TeamsProtectionPolicy' -and $cmdParams.Keys.Count -eq 2 -and
            $cmdParams['Identity'] -ceq $Current.Name -and $cmdParams['Comment'] -ceq "policy $($Current.Name)"
        }
    }

    It 'ExoRequest still refuses a token the record does not provide' {
        $Spec = @{ cmdlets = @(@{ cmdlet = 'Set-X'; params = @{ Identity = '%Missing%' } }) } | ConvertTo-Spec
        { Invoke-CIPPBaselineExoRequest -Remediate $Spec -TenantFilter 'contoso.onmicrosoft.com' -Current ([PSCustomObject]@{ Name = 'a' }) } | Should -Throw '*unresolved token*'
    }
}
