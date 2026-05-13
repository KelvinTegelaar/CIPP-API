function Test-CIPPDynamicGroupFilter {
    <#
    .SYNOPSIS
        Returns a sanitized PowerShell condition string for a dynamic tenant group rule.
    .DESCRIPTION
        Validates all user-controlled inputs (property, operator, values) against allowlists
        and sanitizes values before building the condition string. Returns a safe condition
        string suitable for use in [ScriptBlock]::Create().

        This replaces the old pattern of directly interpolating unsanitized user input into
        scriptblock strings, which was vulnerable to code injection.
    .PARAMETER Rule
        A single rule object with .property, .operator, and .value fields.
    .PARAMETER TenantGroupMembersCache
        Hashtable of group memberships keyed by group ID.
    .OUTPUTS
        [string] A sanitized PowerShell condition string, or $null if validation fails.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        $Rule,
        [Parameter(Mandatory = $false)]
        [hashtable]$TenantGroupMembersCache = @{}
    )

    $AllowedOperators = @('eq', 'ne', 'like', 'notlike', 'in', 'notin', 'contains', 'notcontains')
    $AllowedProperties = @('delegatedAccessStatus', 'availableLicense', 'availableServicePlan', 'tenantGroupMember', 'customVariable')

    # Regex for sanitizing string values - block characters that enable code injection
    $SafeValueRegex = [regex]'^[^;|`\$\{\}\(\)]*$'
    # Regex for GUID validation
    $GuidRegex = [regex]'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    # Regex for safe identifiers (variable names, plan names, etc.)
    $SafeIdentifierRegex = [regex]'^[a-zA-Z0-9_.\-\s\(\)]+$'

    $Property = $Rule.property
    $Operator = [string]($Rule.operator)
    $OperatorLower = $Operator.ToLower()
    $Value = $Rule.value

    # Validate operator
    if ($OperatorLower -notin $AllowedOperators) {
        Write-Warning "Blocked invalid operator '$Operator' in dynamic group rule for property '$Property'"
        return $null
    }

    # Validate property
    if ($Property -notin $AllowedProperties) {
        Write-Warning "Blocked invalid property '$Property' in dynamic group rule"
        return $null
    }

    # Helper: sanitize a single string value for safe embedding in a quoted string
    function Protect-StringValue {
        param([string]$InputValue)
        # Escape single quotes by doubling them (PowerShell string escaping)
        $escaped = $InputValue -replace "'", "''"
        # Block any remaining injection characters
        if (-not $SafeValueRegex.IsMatch($escaped)) {
            Write-Warning "Blocked unsafe value: '$InputValue'"
            return $null
        }
        return $escaped
    }

    # Helper: sanitize and format an array of string values for embedding in @('a','b')
    function Protect-StringArray {
        param([array]$InputValues)
        $sanitized = foreach ($v in $InputValues) {
            $clean = Protect-StringValue -InputValue ([string]$v)
            if ($null -eq $clean) { return $null }
            "'$clean'"
        }
        return "@($($sanitized -join ', '))"
    }

    switch ($Property) {
        'delegatedAccessStatus' {
            $safeValue = Protect-StringValue -InputValue ([string]$Value.value)
            if ($null -eq $safeValue) { return $null }
            return "`$_.delegatedPrivilegeStatus -$OperatorLower '$safeValue'"
        }
        'availableLicense' {
            if ($OperatorLower -in @('in', 'notin')) {
                $arrayValues = @(if ($Value -is [array]) { $Value.guid } else { @($Value.guid) })
                # Validate each GUID
                foreach ($g in $arrayValues) {
                    if (![string]::IsNullOrEmpty($g) -and -not $GuidRegex.IsMatch($g)) {
                        Write-Warning "Blocked invalid GUID in availableLicense rule: '$g'"
                        return $null
                    }
                }
                $arrayAsString = ($arrayValues | Where-Object { ![string]::IsNullOrEmpty($_) }) | ForEach-Object { "'$_'" }
                if ($OperatorLower -eq 'in') {
                    return "(`$_.skuId | Where-Object { `$_ -in @($($arrayAsString -join ', ')) }).Count -gt 0"
                } else {
                    return "(`$_.skuId | Where-Object { `$_ -in @($($arrayAsString -join ', ')) }).Count -eq 0"
                }
            } else {
                $guid = [string]$Value.guid
                if (![string]::IsNullOrEmpty($guid) -and -not $GuidRegex.IsMatch($guid)) {
                    Write-Warning "Blocked invalid GUID in availableLicense rule: '$guid'"
                    return $null
                }
                return "`$_.skuId -$OperatorLower '$guid'"
            }
        }
        'availableServicePlan' {
            if ($OperatorLower -in @('in', 'notin')) {
                $arrayValues = @(if ($Value -is [array]) { $Value.value } else { @($Value.value) })
                foreach ($v in $arrayValues) {
                    if (![string]::IsNullOrEmpty($v) -and -not $SafeIdentifierRegex.IsMatch($v)) {
                        Write-Warning "Blocked invalid service plan name: '$v'"
                        return $null
                    }
                }
                $arrayAsString = ($arrayValues | Where-Object { ![string]::IsNullOrEmpty($_) }) | ForEach-Object { "'$_'" }
                if ($OperatorLower -eq 'in') {
                    return "(`$_.servicePlans | Where-Object { `$_ -in @($($arrayAsString -join ', ')) }).Count -gt 0"
                } else {
                    return "(`$_.servicePlans | Where-Object { `$_ -in @($($arrayAsString -join ', ')) }).Count -eq 0"
                }
            } else {
                $safeValue = Protect-StringValue -InputValue ([string]$Value.value)
                if ($null -eq $safeValue) { return $null }
                return "`$_.servicePlans -$OperatorLower '$safeValue'"
            }
        }
        'tenantGroupMember' {
            if ($OperatorLower -in @('in', 'notin')) {
                $ReferencedGroupIds = @($Value.value)
                # Validate group IDs are GUIDs
                foreach ($gid in $ReferencedGroupIds) {
                    if (![string]::IsNullOrEmpty($gid) -and -not $GuidRegex.IsMatch($gid)) {
                        Write-Warning "Blocked invalid group ID in tenantGroupMember rule: '$gid'"
                        return $null
                    }
                }

                $AllMembers = [System.Collections.Generic.HashSet[string]]::new()
                foreach ($GroupId in $ReferencedGroupIds) {
                    if ($TenantGroupMembersCache.ContainsKey($GroupId)) {
                        foreach ($MemberId in $TenantGroupMembersCache[$GroupId]) {
                            [void]$AllMembers.Add($MemberId)
                        }
                    }
                }

                $MemberArray = $AllMembers | ForEach-Object { "'$_'" }
                $MemberArrayString = $MemberArray -join ', '

                if ($OperatorLower -eq 'in') {
                    return "`$_.customerId -in @($MemberArrayString)"
                } else {
                    return "`$_.customerId -notin @($MemberArrayString)"
                }
            } else {
                $ReferencedGroupId = [string]$Value.value
                if (![string]::IsNullOrEmpty($ReferencedGroupId) -and -not $GuidRegex.IsMatch($ReferencedGroupId)) {
                    Write-Warning "Blocked invalid group ID: '$ReferencedGroupId'"
                    return $null
                }
                return "`$_.customerId -$OperatorLower `$script:TenantGroupMembersCache['$ReferencedGroupId']"
            }
        }
        'customVariable' {
            $VariableName = if ($Value.variableName -is [string]) {
                $Value.variableName
            } elseif ($Value.variableName.value) {
                $Value.variableName.value
            } else {
                [string]$Value.variableName
            }
            # Validate variable name - alphanumeric, underscores, hyphens, dots only
            if (-not $SafeIdentifierRegex.IsMatch($VariableName)) {
                Write-Warning "Blocked invalid custom variable name: '$VariableName'"
                return $null
            }
            $ExpectedValue = Protect-StringValue -InputValue ([string]$Value.value)
            if ($null -eq $ExpectedValue) { return $null }

            switch ($OperatorLower) {
                'eq' {
                    return "(`$_.customVariables.ContainsKey('$VariableName') -and `$_.customVariables['$VariableName'].Value -eq '$ExpectedValue')"
                }
                'ne' {
                    return "(-not `$_.customVariables.ContainsKey('$VariableName') -or `$_.customVariables['$VariableName'].Value -ne '$ExpectedValue')"
                }
                'like' {
                    return "(`$_.customVariables.ContainsKey('$VariableName') -and `$_.customVariables['$VariableName'].Value -like '*$ExpectedValue*')"
                }
                'notlike' {
                    return "(-not `$_.customVariables.ContainsKey('$VariableName') -or `$_.customVariables['$VariableName'].Value -notlike '*$ExpectedValue*')"
                }
                default {
                    Write-Warning "Unsupported operator '$OperatorLower' for customVariable"
                    return $null
                }
            }
        }
        default {
            Write-Warning "Unknown property type: $Property"
            return $null
        }
    }
}
