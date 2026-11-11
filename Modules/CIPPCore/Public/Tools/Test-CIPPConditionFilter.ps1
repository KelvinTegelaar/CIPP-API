function Test-CIPPConditionFilter {
    <#
    .SYNOPSIS
        Returns a sanitized PowerShell condition string for an audit log / delta query condition.
    .DESCRIPTION
        Validates operator and property name against allowlists, embeds the value as an escaped
        single-quoted literal and parses the result to confirm it is a single comparison over that
        literal before returning a string suitable for [ScriptBlock]::Create().
    .PARAMETER Condition
        A single condition object with Property.label, Operator.value, and Input.value.
    .OUTPUTS
        [string] A sanitized PowerShell condition string, or $null if validation fails.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        $Condition
    )

    $AllowedOperators = @(
        'eq', 'ne', 'like', 'notlike', 'match', 'notmatch',
        'gt', 'lt', 'ge', 'le', 'in', 'notin',
        'contains', 'notcontains'
    )
    $SafePropertyRegex = [regex]'^[a-zA-Z0-9_.]+$'
    $UnsafeValueRegex = [regex]'[;|`\$\{\}]'

    $propertyName = [string]$Condition.Property.label
    $operatorValue = ([string]$Condition.Operator.value).ToLower()
    $inputValue = $Condition.Input.value

    if ($operatorValue -notin $AllowedOperators) {
        Write-Warning "Blocked invalid operator '$($Condition.Operator.value)' in condition for property '$propertyName'"
        return $null
    }

    if (-not $SafePropertyRegex.IsMatch($propertyName)) {
        Write-Warning "Blocked invalid property name '$propertyName' in condition"
        return $null
    }

    if ($inputValue -is [array]) {
        $expectedValues = [System.Collections.Generic.List[string]]::new()
        $sanitizedItems = foreach ($item in $inputValue) {
            $itemStr = [string]$item
            if ($UnsafeValueRegex.IsMatch($itemStr)) {
                Write-Warning "Blocked unsafe value in array for property '$propertyName': '$itemStr'"
                return $null
            }
            $expectedValues.Add($itemStr)
            "'$(ConvertTo-CIPPScriptBlockValue -Value $itemStr)'"
        }
        if ($null -eq $sanitizedItems) { return $null }
        $value = "@($($sanitizedItems -join ', '))"
    } else {
        $valueStr = [string]$inputValue
        if ($UnsafeValueRegex.IsMatch($valueStr)) {
            Write-Warning "Blocked unsafe value for property '$propertyName': '$valueStr'"
            return $null
        }
        $expectedValues = @($valueStr)
        $value = "'$(ConvertTo-CIPPScriptBlockValue -Value $valueStr)'"
    }

    $leftSide = "`$(`$_.$propertyName)"
    $conditionString = "$leftSide -$operatorValue $value"

    # Parse check: one binary comparison, our left side, and a right side made only of the string constant(s) we embedded.
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($conditionString, [ref]$tokens, [ref]$parseErrors)
    $expression = $null
    if ($parseErrors.Count -eq 0 -and $ast.EndBlock.Statements.Count -eq 1) {
        $pipeline = $ast.EndBlock.Statements[0]
        if ($pipeline -is [System.Management.Automation.Language.PipelineAst] -and $pipeline.PipelineElements.Count -eq 1 -and
            $pipeline.PipelineElements[0] -is [System.Management.Automation.Language.CommandExpressionAst]) {
            $expression = $pipeline.PipelineElements[0].Expression
        }
    }
    if ($expression -isnot [System.Management.Automation.Language.BinaryExpressionAst] -or $expression.Left.Extent.Text -ne $leftSide) {
        Write-Warning "Blocked condition for property '$propertyName': it did not parse as a single comparison"
        return $null
    }

    $allowedRightNodes = @(
        [System.Management.Automation.Language.StringConstantExpressionAst]
        [System.Management.Automation.Language.ArrayExpressionAst]
        [System.Management.Automation.Language.ArrayLiteralAst]
        [System.Management.Automation.Language.StatementBlockAst]
        [System.Management.Automation.Language.PipelineAst]
        [System.Management.Automation.Language.CommandExpressionAst]
    )
    $rightNodes = $expression.Right.FindAll({ $true }, $true)
    foreach ($node in $rightNodes) {
        if ($node.GetType() -notin $allowedRightNodes) {
            Write-Warning "Blocked condition for property '$propertyName': value contained code ($($node.GetType().Name))"
            return $null
        }
    }
    $parsedValues = @($rightNodes | Where-Object { $_ -is [System.Management.Automation.Language.StringConstantExpressionAst] } | ForEach-Object { $_.Value })
    $expectedList = @($expectedValues)
    if ($parsedValues.Count -ne $expectedList.Count) {
        Write-Warning "Blocked condition for property '$propertyName': value count changed after escaping"
        return $null
    }
    for ($i = 0; $i -lt $expectedList.Count; $i++) {
        if (-not [string]::Equals($parsedValues[$i], $expectedList[$i], [System.StringComparison]::Ordinal)) {
            Write-Warning "Blocked condition for property '$propertyName': value changed after escaping"
            return $null
        }
    }

    return $conditionString
}
