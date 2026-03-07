function Test-CustomScriptSecurity {
    <#
    .SYNOPSIS
        Validates custom script security constraints using AST parsing with allowlist approach

    .PARAMETER ScriptContent
        The script content to validate
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptContent
    )

    # Parse the script into an AST
    $Errors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseInput($ScriptContent, [ref]$null, [ref]$Errors)

    if ($Errors) {
        throw "Script parsing failed: $($Errors[0].Message)"
    }

    # Check for += operator using AST
    $AssignmentStatements = $Ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst]
    }, $true)

    foreach ($assignment in $AssignmentStatements) {
        if ($assignment.Operator -eq [System.Management.Automation.Language.TokenKind]::PlusEquals) {
            throw 'The += operator is not allowed in custom scripts. Use array expansion or collection methods instead.'
        }
    }

    # ALLOWLIST: Only these commands are permitted
    $AllowedCommands = @(
        # Data manipulation cmdlets
        'ForEach-Object', 'Where-Object', 'Select-Object', 'Group-Object',
        'Measure-Object', 'Sort-Object', 'Compare-Object', 'Get-Member',

        # Utility cmdlets
        'Get-Date', 'Get-Random', 'New-Object', 'New-Guid', 'New-TimeSpan',
        'ConvertTo-Json', 'ConvertFrom-Json', 'Write-Output', 'Write-Host',

        # CIPP data access (read-only)
        'New-CIPPDbRequest', 'Get-CIPPDbItem'
    )

    # Find all command invocations (exclude hashtable key assignments and property access)
    $Commands = $Ast.FindAll({
        param($node)
        if ($node -is [System.Management.Automation.Language.CommandAst]) {
            # Exclude if this is inside a hashtable
            $current = $node.Parent
            while ($current) {
                if ($current -is [System.Management.Automation.Language.HashtableAst]) {
                    return $false
                }
                $current = $current.Parent
            }

            return $true
        }
        return $false
    }, $true)

    foreach ($cmd in $Commands) {
        $commandName = $cmd.GetCommandName()
        if (-not $commandName) { continue }

        # Check if command is in allowlist
        if ($commandName -notin $AllowedCommands) {
            # Get the extent text to show context
            $cmdText = $cmd.Extent.Text
            $lineNumber = $cmd.Extent.StartLineNumber
            throw "Security violation at line $lineNumber`: Command '$commandName' is not in the allowed list.`nContext: $cmdText`n`nOnly these commands are permitted: $($AllowedCommands -join ', ')"
        }
    }

    # Check for dangerous .NET types - block all direct .NET type usage except approved ones
    $TypeExpressions = $Ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.TypeExpressionAst]
    }, $true)

    # Allowed types with proper namespace qualification
    $AllowedTypes = @(
        'PSCustomObject', 'PSObject',
        'System.String', 'System.Int32', 'System.Int64', 'System.Boolean',
        'System.Collections.ArrayList', 'System.Collections.Hashtable',
        'System.DateTime', 'System.TimeSpan', 'System.Guid',
        'System.Object', 'System.Array'
    )

    foreach ($typeExpr in $TypeExpressions) {
        $typeName = $typeExpr.TypeName.FullName

        # Check if it's an allowed type (exact match)
        if ($typeName -notin $AllowedTypes) {
            throw "Security violation: .NET type '$typeName' is not allowed. Only these types are permitted: $($AllowedTypes -join ', ')"
        }
    }
}
