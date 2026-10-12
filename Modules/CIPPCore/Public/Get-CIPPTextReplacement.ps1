function Get-CIPPTextReplacement {
    <#
    .SYNOPSIS
        Replaces text with tenant specific values
    .DESCRIPTION
        Helper function to replace text with tenant specific values
    .PARAMETER TenantFilter
        The tenant filter to use
    .PARAMETER Text
        The text to replace
    .EXAMPLE
        Get-CIPPTextReplacement -TenantFilter 'contoso.com' -Text 'Hello %tenantname%'
    #>
    param (
        [string]$TenantFilter = $env:TenantID,
        $Text,
        [switch]$EscapeForJson
    )
    # Escapes a replacement value so it can be safely spliced into a serialized JSON
    # string literal. Handles quotes, backslashes, newlines, tabs and control chars.
    function ConvertTo-CIPPJsonEscapedString {
        param($Value)
        if ($null -eq $Value) { return '' }
        $Encoded = [string]$Value | ConvertTo-Json -Compress
        # Strip the surrounding quotes ConvertTo-Json adds, leaving just the escaped body.
        return $Encoded.Substring(1, $Encoded.Length - 2)
    }

    # -replace reads the replacement string as a substitution pattern, so '$&', '$1' and '${x}' in a
    # variable's value would be expanded instead of written out. Every value here is literal text,
    # so a lone $ is doubled - the escape the regex engine recognises for one literal dollar sign.
    function ConvertTo-CIPPLiteralReplacement {
        param($Value)
        if ($null -eq $Value) { return '' }
        return ([string]$Value).Replace('$', '$$')
    }

    # Substitutes one %token%. Escaping is decided here rather than at each site so the built-in
    # tenant tokens get exactly what the custom variables get: a value CIPP does not control -
    # a tenant display name is free text - is never spliced into JSON unescaped.
    function Set-CIPPReplacementToken {
        param([string]$Text, [string]$Token, $Value, [bool]$Escape)
        # A token whose source is unset resolves to empty, which is what it has always done.
        if ($null -eq $Value) { $Value = '' }
        $Replacement = if ($Escape) { ConvertTo-CIPPJsonEscapedString -Value $Value } else { [string]$Value }
        return $Text -replace [regex]::Escape($Token), (ConvertTo-CIPPLiteralReplacement -Value $Replacement)
    }

    # Renders a typed variable as a bare JSON literal. Returns $null for an untyped variable, for the
    # default string type, and when the value does not actually parse as the type it claims - the
    # caller then substitutes it the way it always did, which keeps existing variables byte-identical
    # and lets a mistyped one fail as a readable error rather than a parse error here.
    function ConvertTo-CIPPJsonLiteral {
        param($Value, [string]$VariableType)

        if ([string]::IsNullOrWhiteSpace($VariableType)) { return $null }

        $Text = ([string]$Value).Trim()
        switch ($VariableType.ToLower()) {
            'integer' {
                $Parsed = [long]0
                if ([long]::TryParse($Text, [ref]$Parsed)) { return "$Parsed" }
                return $null
            }
            'boolean' {
                if ($Text -in @('true', '1', 'yes')) { return 'true' }
                if ($Text -in @('false', '0', 'no')) { return 'false' }
                return $null
            }
            'json' {
                try {
                    $Object = ConvertFrom-Json -InputObject $Text -Depth 100 -NoEnumerate -ErrorAction Stop
                    return (ConvertTo-Json -InputObject $Object -Depth 100 -Compress)
                } catch {
                    return $null
                }
            }
            default { return $null }
        }
    }

    # A list variable holds a JSON array. Used as an array element it is spliced in as several
    # elements; filling a whole slot it is the array; inside a longer string it is comma-joined.
    function Expand-CIPPListToken {
        param([string]$Text, [string]$Token, $Value, [bool]$Escape)
        try {
            $Items = @(ConvertFrom-Json -InputObject ([string]$Value) -Depth 100 -NoEnumerate -ErrorAction Stop | ForEach-Object { $_ })
        } catch {
            return $null
        }
        $Quoted = [regex]::Escape('"{0}"' -f $Token)
        $Encoded = @(foreach ($Item in $Items) { ConvertTo-Json -InputObject $Item -Depth 100 -Compress })
        if ($Encoded.Count -gt 0) {
            $Text = $Text -replace "(?<=[\[,]\s*)$Quoted(?=\s*[\],])", (ConvertTo-CIPPLiteralReplacement -Value ($Encoded -join ','))
        } else {
            $Text = $Text -replace ",\s*$Quoted(?=\s*[\],])", ''
            $Text = $Text -replace "(?<=\[\s*)$Quoted\s*,?\s*", ''
        }
        $Text = $Text -replace $Quoted, (ConvertTo-CIPPLiteralReplacement -Value ('[{0}]' -f ($Encoded -join ',')))
        return Set-CIPPReplacementToken -Text $Text -Token $Token -Value ($Items -join ', ') -Escape $Escape
    }

    if ($Text -isnot [string]) {
        return , $Text
    }

    # Without a tenant context, skip replacement lookups and return input as-is.
    if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
        return $Text
    }

    # Every token is %name%, so text without a '%' cannot change and needs no lookups
    if (-not $Text.Contains('%')) {
        return $Text
    }

    $ReservedVariables = @(
        '%serial%',
        '%systemroot%',
        '%systemdrive%',
        '%system32%',
        '%osdrive%',
        '%temp%',
        '%tenantid%',
        '%tenantfilter%',
        '%initialdomain%',
        '%tenantname%',
        '%partnertenantid%',
        '%samappid%',
        '%userprofile%',
        '%username%',
        '%userdomain%',
        '%windir%',
        '%programfiles%',
        '%programfiles(x86)%',
        '%programdata%',
        '%cippuserschema%',
        '%cippurl%',
        '%defaultdomain%',
        '%organizationid%',
        '%globaladminsid%',
        '%deviceadminsid%'
    )

    # The partner tenant is resolved like any other, so addressing it by ID reaches its per-tenant
    # variables and built-in tokens the same way its domain name does. When it is not in the tenant
    # cache, Get-Tenants returns nothing for the partner GUID without triggering a cache rebuild,
    # and the raw filter still serves as the partition key.
    $Tenant = Get-Tenants -TenantFilter $TenantFilter
    $CustomerId = if ($Tenant.customerId) { $Tenant.customerId } else { $TenantFilter }

    #connect to table, get replacement map. The replacement map will allow users to create custom vars that get replaced by the actual values per tenant. Example:
    # %WallPaperPath% gets replaced by RowKey WallPaperPath which is set to C:\Wallpapers for tenant 1, and D:\Wallpapers for tenant 2

    # Global Variables
    $ReplaceTable = Get-CIPPTable -tablename 'CippReplacemap'
    $GlobalMap = Get-CIPPAzDataTableEntity @ReplaceTable -Filter "PartitionKey eq 'AllTenants'"
    # Values are kept unescaped here and escaped at substitution time, so every token - custom and
    # built-in alike - goes through one code path. A typed variable is rendered from the raw value
    # too: escaping is a no-op for a number, and would break a JSON one.
    $Vars = @{}
    $VarTypes = @{}
    if ($GlobalMap) {
        foreach ($Var in $GlobalMap) {
            if (-not $Var.PSObject.Properties['Value']) { continue }
            $Vars[$Var.RowKey] = $Var.Value
            $VarTypes[$Var.RowKey] = $Var.VariableType
        }
    }

    if ($Tenant) {
        # Tenant Specific Variables
        $ReplaceMap = Get-CIPPAzDataTableEntity @ReplaceTable -Filter "PartitionKey eq '$CustomerId'"
        # If no results found by customerId, try by defaultDomainName
        if (!$ReplaceMap) {
            $ReplaceMap = Get-CIPPAzDataTableEntity @ReplaceTable -Filter "PartitionKey eq '$($Tenant.defaultDomainName)'"
        }
        if ($ReplaceMap) {
            foreach ($Var in $ReplaceMap) {
                if (-not $Var.PSObject.Properties['Value']) { continue }
                $Vars[$Var.RowKey] = $Var.Value
                $VarTypes[$Var.RowKey] = $Var.VariableType
            }
        }
    }
    # Replace custom variables
    foreach ($Replace in $Vars.GetEnumerator()) {
        $String = '%{0}%' -f $Replace.Key
        if ($string -notin $ReservedVariables) {
            if ("$($VarTypes[$Replace.Key])" -eq 'list') {
                $Expanded = Expand-CIPPListToken -Text $Text -Token $String -Value $Replace.Value -Escape $EscapeForJson.IsPresent
                if ($null -ne $Expanded) {
                    $Text = $Expanded
                    continue
                }
            }
            # A variable declared as integer, boolean or json is written as a JSON literal when it
            # fills an entire string slot, so a numeric setting receives 300 rather than "300" and
            # behaves exactly like a value typed into the template by hand.
            #
            # The declared type drives this, not the caller's -EscapeForJson switch: a type is
            # something an operator opts into on a single variable, so it can be honoured everywhere
            # without changing what any existing variable does. Untyped variables - which is every
            # variable that predates this - return $null here and fall through to the substitution
            # they have always had.
            #
            # Only the whole-slot form is unquoted; a variable embedded in a longer string is still
            # part of that string. A value that does not parse as its declared type also falls
            # through, so a mistyped variable degrades to the old behaviour instead of emitting
            # invalid JSON.
            $Literal = ConvertTo-CIPPJsonLiteral -Value $Vars[$Replace.Key] -VariableType $VarTypes[$Replace.Key]
            if ($null -ne $Literal) {
                $Text = $Text -replace ('"{0}"' -f [regex]::Escape($String)), (ConvertTo-CIPPLiteralReplacement -Value $Literal)
            }
            $Text = Set-CIPPReplacementToken -Text $Text -Token $String -Value $Replace.Value -Escape $EscapeForJson.IsPresent
        }
    }
    #default replacements for all tenants: %tenantid% becomes $tenant.customerId, %tenantfilter% becomes $tenant.defaultDomainName, %tenantname% becomes $tenant.displayName
    $BuiltInVars = [ordered]@{
        '%tenantid%'        = $Tenant.customerId
        '%organizationid%'  = $Tenant.customerId
        '%tenantfilter%'    = $Tenant.defaultDomainName
        '%defaultdomain%'   = $Tenant.defaultDomainName
        '%initialdomain%'   = $Tenant.initialDomainName
        '%tenantname%'      = $Tenant.displayName
        # Partner specific replacements
        '%partnertenantid%' = $env:TenantID
        '%samappid%'        = $env:ApplicationID
    }
    foreach ($BuiltIn in $BuiltInVars.GetEnumerator()) {
        $Text = Set-CIPPReplacementToken -Text $Text -Token $BuiltIn.Key -Value $BuiltIn.Value -Escape $EscapeForJson.IsPresent
    }

    if ($Text -match '%cippuserschema%') {
        $Schema = Get-CIPPSchemaExtensions | Where-Object { $_.id -match '_cippUser' } | Select-Object -First 1
        $Text = Set-CIPPReplacementToken -Text $Text -Token '%cippuserschema%' -Value $Schema.id -Escape $EscapeForJson.IsPresent
    }

    if ($Text -match '%cippurl%') {
        $ConfigTable = Get-CIPPTable -tablename 'Config'
        $Config = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'InstanceProperties' and RowKey eq 'CIPPURL'"
        if ($Config) {
            $Text = Set-CIPPReplacementToken -Text $Text -Token '%cippurl%' -Value $Config.Value -Escape $EscapeForJson.IsPresent
        }
    }

    if ($Text -match '%(globaladmin|deviceadmin)sid%') {
        # A directory role's object id never changes once activated, so the Roles cache is authoritative.
        $RoleSidTokens = @{
            '%globaladminsid%' = '62e90394-69f5-4237-9190-012177145e10'
            '%deviceadminsid%' = '9f06204d-73c1-4d4c-880a-6edb90606fd8'
        }
        $RoleObjectIds = @{}
        foreach ($Role in @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'Roles' -Fields 'id', 'roleTemplateId')) {
            if ($Role.roleTemplateId) { $RoleObjectIds[$Role.roleTemplateId] = $Role.id }
        }
        foreach ($Token in $RoleSidTokens.GetEnumerator()) {
            if ($Text -notmatch $Token.Key) { continue }
            $RoleObjectId = $RoleObjectIds[$Token.Value]
            if (-not $RoleObjectId) {
                throw "Cannot resolve $($Token.Key) for ${TenantFilter}: the role is not in the cached directory roles. Sync the Roles & Assignments cache and try again."
            }
            $Text = Set-CIPPReplacementToken -Text $Text -Token $Token.Key -Value (Convert-AzureAdObjectIdToSid -ObjectID $RoleObjectId) -Escape $EscapeForJson.IsPresent
        }
    }
    return $Text
}
