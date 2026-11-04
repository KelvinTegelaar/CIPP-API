function Get-CippSandboxData {
    <#
    .SYNOPSIS
        Pre-fetches the tenant-locked cache data a custom test requests.

    .DESCRIPTION
        Runs on the trusted (FullLanguage) side before the script enters the sandbox.
        Inspects the script AST for Get-CIPPTestData calls, resolves each requested -Type,
        and fetches that data for the supplied tenant via the real Get-CIPPTestData. The
        result is a hashtable keyed by Type that the sandbox proxy serves.

        Because only the requested types for THIS tenant are fetched and injected, the
        sandbox is structurally unable to read any other tenant's data.

        -Type must be a named string literal. Missing, positional and dynamic type names are
        rejected with a clear error. Data is projected to the field manifest, as for built-in tests.

    .PARAMETER ScriptContent
        The (already text-replaced, already validated) script content.

    .PARAMETER TenantFilter
        The tenant to fetch data for.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptContent,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    $Ast = [System.Management.Automation.Language.Parser]::ParseInput($ScriptContent, [ref]$null, [ref]$null)

    $Calls = $Ast.FindAll({
            param($Node)
            $Node -is [System.Management.Automation.Language.CommandAst] -and
            $Node.GetCommandName() -eq 'Get-CIPPTestData'
        }, $true)

    $Data = @{}

    foreach ($Call in $Calls) {
        $Type = $null

        for ($i = 0; $i -lt $Call.CommandElements.Count; $i++) {
            $Element = $Call.CommandElements[$i]
            if ($Element -is [System.Management.Automation.Language.CommandParameterAst] -and $Element.ParameterName -ieq 'Type') {
                $Value = if ($Element.Argument) {
                    $Element.Argument
                } elseif ($i + 1 -lt $Call.CommandElements.Count) {
                    $Call.CommandElements[$i + 1]
                } else {
                    $null
                }
                if ($Value -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                    $Type = $Value.Value
                }
            }
        }

        # Without a type the read would be the tenant's whole reporting partition.
        if ([string]::IsNullOrWhiteSpace($Type)) {
            throw [System.ArgumentException]::new("Custom test sandbox requires a literal -Type for every Get-CIPPTestData call (for example: Get-CIPPTestData -Type 'Users'). Missing, positional, dynamic or computed type names are not supported.")
        }

        if (-not $Data.ContainsKey($Type)) {
            $Data[$Type] = @(Get-CIPPTestData -TenantFilter $TenantFilter -Type $Type)
        }
    }

    return $Data
}
