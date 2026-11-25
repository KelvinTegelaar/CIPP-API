# A Graph or Exchange call without -tenantid runs against the partner tenant. Deliberate partner calls say so with
# -NoAuthCheck; a call with neither has usually just lost its tenant and acts on the partner instead of the customer.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:ModulesRoot = Join-Path $BackendRoot 'Modules'
    $script:Vendored = 'MicrosoftTeams|AzBobbyTables|DNSHealth|HuduAPI'
    $script:Helpers = 'New-GraphGetRequest', 'New-GraphPOSTRequest', 'New-GraphBulkRequest', 'New-ExoRequest', 'New-ExoBulkRequest'
    # Lighthouse and Partner Center URLs are partner-level by design (the exemptions in Get-AuthorisedRequest).
    $script:PartnerUri = '^["'']https://(graph\.microsoft\.com/(beta|v1\.0)/tenantRelationships/|api\.partnercenter\.microsoft\.com/)'
}

Describe 'Graph and Exchange calls' {
    It 'name a tenant or opt into the partner tenant with -NoAuthCheck' {
        $Checked = 0
        $Offenders = foreach ($File in Get-ChildItem -Path $script:ModulesRoot -Include '*.ps1', '*.psm1' -File -Recurse) {
            if ($File.FullName -match "[\\/]($script:Vendored)[\\/]") { continue }
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$null)
            foreach ($Call in $Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] -and $args[0].GetCommandName() -in $script:Helpers }, $true)) {
                $Scoped = $false
                $Elements = $Call.CommandElements
                for ($i = 1; $i -lt $Elements.Count; $i++) {
                    $Element = $Elements[$i]
                    # Splatted arguments can't be read statically.
                    if ($Element -is [System.Management.Automation.Language.VariableExpressionAst] -and $Element.Splatted) { $Scoped = $true; break }
                    if ($Element -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
                    $Name = $Element.ParameterName
                    # -tenant binds to -tenantid as an unambiguous prefix.
                    if ($Name -eq 'NoAuthCheck' -or ($Name.Length -ge 6 -and 'tenantid'.StartsWith($Name, [System.StringComparison]::OrdinalIgnoreCase))) { $Scoped = $true; break }
                    if ($Name -eq 'uri' -and ($Element.Argument ?? $Elements[$i + 1]).Extent.Text -match $script:PartnerUri) { $Scoped = $true; break }
                }
                $Checked++
                if (-not $Scoped) { "$($File.Name):$($Call.Extent.StartLineNumber) $($Call.GetCommandName())" }
            }
        }
        $Checked | Should -BeGreaterThan 2500
        $Offenders | Should -BeNullOrEmpty
    }
}
