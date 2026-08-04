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
                # Re-serialized rather than spliced in verbatim, so whatever reaches the payload is
                # known-valid, compact JSON regardless of how it was stored.
                try {
                    $Object = ConvertFrom-Json -InputObject $Text -Depth 100 -ErrorAction Stop
                    return (ConvertTo-Json -InputObject $Object -Depth 100 -Compress)
                } catch {
                    return $null
                }
            }
            default { return $null }
        }
    }

    if ($Text -isnot [string]) {
        return , $Text
    }

    # Without a tenant context, skip replacement lookups and return input as-is.
    if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
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
        '%organizationid%'
    )

    if ($TenantFilter -ne $env:TenantID) {
        $Tenant = Get-Tenants -TenantFilter $TenantFilter
        $CustomerId = $Tenant.customerId
    } else {
        $CustomerId = $TenantFilter
    }

    #connect to table, get replacement map. The replacement map will allow users to create custom vars that get replaced by the actual values per tenant. Example:
    # %WallPaperPath% gets replaced by RowKey WallPaperPath which is set to C:\Wallpapers for tenant 1, and D:\Wallpapers for tenant 2

    # Global Variables
    $ReplaceTable = Get-CIPPTable -tablename 'CippReplacemap'
    $GlobalMap = Get-CIPPAzDataTableEntity @ReplaceTable -Filter "PartitionKey eq 'AllTenants'"
    $Vars = @{}
    # The declared type of each variable, and its unescaped value. A typed variable is rendered from
    # the raw value: escaping is a no-op for a number, and would break a JSON one.
    $VarTypes = @{}
    $RawVars = @{}
    if ($GlobalMap) {
        foreach ($Var in $GlobalMap) {
            if (-not $Var.PSObject.Properties['Value']) { continue }
            $Val = $Var.Value
            if ($EscapeForJson.IsPresent) {
                $Val = ConvertTo-CIPPJsonEscapedString -Value $Val
            }
            $Vars[$Var.RowKey] = $Val
            $RawVars[$Var.RowKey] = $Var.Value
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
                $Val = $Var.Value
                if ($EscapeForJson.IsPresent) {
                    $Val = ConvertTo-CIPPJsonEscapedString -Value $Val
                }
                $Vars[$Var.RowKey] = $Val
                $RawVars[$Var.RowKey] = $Var.Value
                $VarTypes[$Var.RowKey] = $Var.VariableType
            }
        }
    }
    # Replace custom variables
    foreach ($Replace in $Vars.GetEnumerator()) {
        $String = '%{0}%' -f $Replace.Key
        if ($string -notin $ReservedVariables) {
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
            $Literal = ConvertTo-CIPPJsonLiteral -Value $RawVars[$Replace.Key] -VariableType $VarTypes[$Replace.Key]
            if ($null -ne $Literal) {
                $Text = $Text -replace ('"{0}"' -f [regex]::Escape($String)), $Literal
            }
            $Text = $Text -replace $String, $Replace.Value
        }
    }
    #default replacements for all tenants: %tenantid% becomes $tenant.customerId, %tenantfilter% becomes $tenant.defaultDomainName, %tenantname% becomes $tenant.displayName
    $Text = $Text -replace '%tenantid%', $Tenant.customerId
    $Text = $Text -replace '%organizationid%', $Tenant.customerId
    $Text = $Text -replace '%tenantfilter%', $Tenant.defaultDomainName
    $Text = $Text -replace '%defaultdomain%', $Tenant.defaultDomainName
    $Text = $Text -replace '%initialdomain%', $Tenant.initialDomainName
    $Text = $Text -replace '%tenantname%', $Tenant.displayName

    # Partner specific replacements
    $Text = $Text -replace '%partnertenantid%', $env:TenantID
    $Text = $Text -replace '%samappid%', $env:ApplicationID

    if ($Text -match '%cippuserschema%') {
        $Schema = Get-CIPPSchemaExtensions | Where-Object { $_.id -match '_cippUser' } | Select-Object -First 1
        $Text = $Text -replace '%cippuserschema%', $Schema.id
    }

    if ($Text -match '%cippurl%') {
        $ConfigTable = Get-CIPPTable -tablename 'Config'
        $Config = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'InstanceProperties' and RowKey eq 'CIPPURL'"
        if ($Config) {
            $Text = $Text -replace '%cippurl%', $Config.Value
        }
    }
    return $Text
}
