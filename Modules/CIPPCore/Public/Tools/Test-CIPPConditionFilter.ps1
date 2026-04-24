function Test-CIPPConditionFilter {
    <#
    .SYNOPSIS
        Returns a sanitized PowerShell condition string for an audit log / delta query condition.
    .DESCRIPTION
        Validates operator and property name against allowlists, sanitizes input values,
        then returns a safe condition string suitable for [ScriptBlock]::Create().

        This replaces the old Invoke-Expression pattern which was vulnerable to code injection
        through unsanitized user-controlled fields.
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

    # Operator allowlist - only these PowerShell comparison operators are permitted
    $AllowedOperators = @(
        'eq', 'ne', 'like', 'notlike', 'match', 'notmatch',
        'gt', 'lt', 'ge', 'le', 'in', 'notin',
        'contains', 'notcontains'
    )

    # Property name validation - only alphanumeric, underscores, and dots allowed
    $SafePropertyRegex = [regex]'^[a-zA-Z0-9_.]+$'

    # Value sanitization - block characters that enable code injection
    $UnsafeValueRegex = [regex]'[;|`\$\{\}]'

    $propertyName = $Condition.Property.label
    $operatorValue = $Condition.Operator.value.ToLower()
    $inputValue = $Condition.Input.value

    # Validate operator against allowlist
    if ($operatorValue -notin $AllowedOperators) {
        Write-Warning "Blocked invalid operator '$($Condition.Operator.value)' in condition for property '$propertyName'"
        return $null
    }

    # Validate property name to prevent injection via property paths
    if (-not $SafePropertyRegex.IsMatch($propertyName)) {
        Write-Warning "Blocked invalid property name '$propertyName' in condition"
        return $null
    }

    # Build sanitized condition string
    if ($inputValue -is [array]) {
        # Sanitize each array element
        $sanitizedItems = foreach ($item in $inputValue) {
            $itemStr = [string]$item
            if ($UnsafeValueRegex.IsMatch($itemStr)) {
                Write-Warning "Blocked unsafe value in array for property '$propertyName': '$itemStr'"
                return $null
            }
            $itemStr -replace "'", "''"
        }
        if ($null -eq $sanitizedItems) { return $null }
        $arrayAsString = $sanitizedItems | ForEach-Object { "'$_'" }
        $value = "@($($arrayAsString -join ', '))"
    } else {
        $valueStr = [string]$inputValue
        if ($UnsafeValueRegex.IsMatch($valueStr)) {
            Write-Warning "Blocked unsafe value for property '$propertyName': '$valueStr'"
            return $null
        }
        $value = "'$($valueStr -replace "'", "''")'"
    }

    return "`$(`$_.$propertyName) -$operatorValue $value"
}
