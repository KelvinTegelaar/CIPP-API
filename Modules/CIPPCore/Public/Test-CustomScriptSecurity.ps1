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

    # Block scoped and namespace-qualified variable access (e.g., $env:, $global:, $script:)
    $VariableExpressions = $Ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.VariableExpressionAst]
    }, $true)

    foreach ($variableExpr in $VariableExpressions) {
        $variablePath = $variableExpr.VariablePath
        $userPath = $variablePath.UserPath

        # Block access to the tenant lock variable used for data access safety
        if ($userPath -eq 'CIPPLockedTenant') {
            $lineNumber = $variableExpr.Extent.StartLineNumber
            throw "Security violation at line $lineNumber`: Access to internal variable 'CIPPLockedTenant' is not allowed."
        }

        if ($userPath -match '^[^:]+:') {
            $lineNumber = $variableExpr.Extent.StartLineNumber
            throw "Security violation at line $lineNumber`: Scoped/namespace-qualified variable access is not allowed ('$userPath'). Avoid variables such as `$env:, `$global:, and `$script:."
        }
    }

    # ALLOWLIST: shared with the sandbox runspace so validator and execution never drift.
    $AllowedCommands = Get-CippCustomScriptAllowedCommand

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

    # The checks below are not a security boundary (ConstrainedLanguage is) — they catch the
    # most common patterns that pass validation but fail under CLM at run time, so the user
    # gets a helpful message at save time instead of a confusing error during Run Test.

    # Block [pscustomobject]/[psobject] conversions: hashtable-to-object conversion is not
    # supported under ConstrainedLanguage.
    $ConvertExpressions = $Ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.ConvertExpressionAst]
    }, $true)

    $BlockedConvertTypes = @('pscustomobject', 'psobject',
        'System.Management.Automation.PSObject', 'System.Management.Automation.PSCustomObject')

    foreach ($convert in $ConvertExpressions) {
        if ($convert.Type.TypeName.FullName -in $BlockedConvertTypes) {
            $lineNumber = $convert.Extent.StartLineNumber
            throw "Security violation at line $lineNumber`: [pscustomobject]/[psobject] conversions are not supported (custom tests run in ConstrainedLanguage). Build result rows with Select-Object @{Name='X'; Expression={ ... }} and return a hashtable, e.g. @{ CIPPStatus = 'Info'; CIPPResults = `$rows }."
        }
    }

    # Block reflection / .NET member access reachable from allowed type literals
    # (e.g. [System.String].Assembly.GetType(...)). CLM blocks these at run time anyway.
    $ReflectionMembers = @(
        'Assembly', 'Module', 'BaseType', 'DeclaringType', 'GetType',
        'GetMethod', 'GetMethods', 'GetProperty', 'GetProperties',
        'GetField', 'GetFields', 'GetMember', 'GetMembers',
        'GetConstructor', 'GetConstructors', 'InvokeMember'
    )

    $MemberExpressions = $Ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.MemberExpressionAst]
    }, $true)

    foreach ($member in $MemberExpressions) {
        if ($member.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
            $member.Member.Value -in $ReflectionMembers) {
            $lineNumber = $member.Extent.StartLineNumber
            throw "Security violation at line $lineNumber`: reflection / .NET member access ('$($member.Member.Value)') is not allowed in custom tests."
        }
    }

    # Require a literal -Type on Get-CIPPTestData so the sandbox can pre-fetch its data.
    $TestDataCalls = $Ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst] -and
        $node.GetCommandName() -eq 'Get-CIPPTestData'
    }, $true)

    foreach ($call in $TestDataCalls) {
        for ($i = 0; $i -lt $call.CommandElements.Count; $i++) {
            $element = $call.CommandElements[$i]
            if ($element -is [System.Management.Automation.Language.CommandParameterAst] -and $element.ParameterName -ieq 'Type') {
                $value = if ($element.Argument) {
                    $element.Argument
                } elseif ($i + 1 -lt $call.CommandElements.Count) {
                    $call.CommandElements[$i + 1]
                } else {
                    $null
                }
                if ($value -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) {
                    $lineNumber = $call.Extent.StartLineNumber
                    throw "Security violation at line $lineNumber`: Get-CIPPTestData -Type must be a literal value (for example: -Type 'Users'). Dynamic or computed type names are not supported."
                }
            }
        }
    }
}
