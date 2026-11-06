# A tenant group runs an endpoint's All Tenants path with the request scope narrowed to the group. Only endpoints marked
# '.FUNCTIONALITY Entrypoint,TenantGroup' accept one, and a marked endpoint must reach its tenants through something that
# honours that scope, or the group view shows every tenant. What honours the scope is worked out from the code, not listed.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $ModulesRoot = Join-Path $BackendRoot 'Modules'
    $Parse = { param($Path) [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null) }
    $Commands = { param($Ast) @($Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)) }

    # A call covers the whole scoped estate unless it names one tenant: -TenantFilter or -tenantid given a variable or
    # a literal other than AllTenants. Get-Tenants -TenantFilter $Tenant validates one tenant; Get-Tenants lists them all.
    $script:EstateCall = {
        param($Command)
        $Elements = $Command.CommandElements
        for ($i = 1; $i -lt $Elements.Count; $i++) {
            $Element = $Elements[$i]
            if ($Element -is [System.Management.Automation.Language.CommandParameterAst] -and $Element.ParameterName -in 'TenantFilter', 'tenantid') {
                $Argument = $Element.Argument ?? $(if ($i + 1 -lt $Elements.Count) { $Elements[$i + 1] })
                if ($Argument -is [System.Management.Automation.Language.StringConstantExpressionAst]) { return $Argument.Value -eq 'AllTenants' }
                if ($Argument -is [System.Management.Automation.Language.VariableExpressionAst]) { return $false }
            }
        }
        $true
    }

    $Helpers = @{}
    foreach ($File in Get-ChildItem -Path $ModulesRoot -Filter '*.ps1' -File -Recurse) {
        if ($File.FullName -notlike '*HTTP Functions*') { $Helpers[$File.BaseName] = & $Parse $File.FullName }
    }
    # Functions that read the request scope themselves
    $script:Sources = @($Helpers.Keys.Where({ $Helpers[$_].Extent.Text -match 'CippAllowedTenantsStorage|Get-CippRequestContext' }))

    # Functions that reach the whole estate through one of them, however many calls down. Handing a tenant on to such a
    # function only counts for one with an AllTenants path of its own; request plumbing passes on the one tenant it was given.
    $CallsOf = @{}
    foreach ($Name in $Helpers.Keys) { $CallsOf[$Name] = & $Commands $Helpers[$Name] }
    $Estate = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    do {
        $Added = 0
        foreach ($Name in $Helpers.Keys) {
            if ($Estate.Contains($Name)) { continue }
            $HasAllTenantsPath = $Helpers[$Name].Extent.Text -match "'AllTenants'"
            $Reaches = $CallsOf[$Name].Where({ $Callee = "$($_.GetCommandName())"; ($Estate.Contains($Callee) -or $script:Sources -contains $Callee) -and ($HasAllTenantsPath -or (& $script:EstateCall $_)) }, 'First')
            if ($Reaches.Count) { $null = $Estate.Add($Name); $Added++ }
        }
    } while ($Added)
    $script:EstateHelpers = $Estate

    $script:Marked = foreach ($File in Get-ChildItem -Path (Join-Path $ModulesRoot 'CIPPHTTP/Public/Entrypoints/HTTP Functions') -Filter 'Invoke-*.ps1' -File -Recurse) {
        $Text = [System.IO.File]::ReadAllText($File.FullName)
        if ($Text -match '\.FUNCTIONALITY\s+([^\r\n]+)' -and $Matches[1] -match '\bTenantGroup\b') {
            [pscustomobject]@{ Name = $File.BaseName; Commands = & $Commands (& $Parse $File.FullName) }
        }
    }
}

Describe 'Endpoints that accept a tenant group' {
    It 'exist, so the check below is not vacuous' {
        @($script:Marked).Count | Should -BeGreaterThan 20
    }

    It 'derive scope readers from the code, leaving single-tenant plumbing out' {
        $script:Sources | Should -Contain 'Get-Tenants'
        $script:EstateHelpers.Contains('Get-CIPPReportPage') | Should -BeTrue
        $script:EstateHelpers.Contains('New-ExoRequest') | Should -BeFalse -Because 'it only validates the one tenant it is given'
        $script:EstateHelpers.Contains('New-GraphGetRequest') | Should -BeFalse
    }

    It 'read their tenants through something that honours the request scope' {
        $Offenders = @($script:Marked.Where({
                    $_.Commands.Where({ $Callee = "$($_.GetCommandName())"; $script:EstateHelpers.Contains($Callee) -or ($script:Sources -contains $Callee -and (& $script:EstateCall $_)) }, 'First').Count -eq 0
                }).Name)
        $Offenders | Should -BeNullOrEmpty -Because 'a group view of an endpoint that never reads the request scope returns every tenant'
    }
}
