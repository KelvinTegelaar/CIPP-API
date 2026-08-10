# Pester tests for Get-CIPPTextReplacement.
#
# Custom variables carry a declared type (string, integer, boolean, json). A typed variable that
# fills an entire JSON string slot is written as a JSON literal, so a numeric Intune setting receives
# 300 rather than "300" and behaves like a value typed into the template by hand.
#
# The type drives that, not the caller's -EscapeForJson switch, because a type is something an
# operator opts into on one variable. The critical property these tests protect is that every
# variable which predates typing - and anything typed 'string' - produces byte-identical output to
# before, on every caller.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CIPPCore/Public/Get-CIPPTextReplacement.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate Get-CIPPTextReplacement.ps1 at $FunctionPath" }

    function Get-CIPPTable { param($tablename) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CIPPSchemaExtensions { }

    . $FunctionPath

    # A CippReplacemap row. Omitting -VariableType produces a row shaped like the ones that existed
    # before typing, which is what the backwards compatibility tests need.
    function New-VariableRow {
        param(
            [Parameter(Mandatory = $true)][string]$Name,
            [Parameter(Mandatory = $true)]$Value,
            [string]$VariableType
        )
        $Row = [pscustomobject]@{ RowKey = $Name; Value = $Value }
        if ($PSBoundParameters.ContainsKey('VariableType')) {
            $Row | Add-Member -NotePropertyName 'VariableType' -NotePropertyValue $VariableType
        }
        return $Row
    }

    function Test-IsValidJson {
        param([string]$Text)
        try { $null = $Text | ConvertFrom-Json -ErrorAction Stop; return $true } catch { return $false }
    }

    # A row written before the Value column existed, or one saved empty.
    function New-ValuelessRow {
        param([Parameter(Mandatory = $true)][string]$Name)
        [pscustomobject]@{ RowKey = $Name }
    }
}

Describe 'Get-CIPPTextReplacement' {
    BeforeEach {
        $script:GlobalRows = @()
        $script:TenantRows = @()

        Mock -CommandName Get-CIPPTable -MockWith { @{} }
        Mock -CommandName Get-Tenants -MockWith {
            [pscustomobject]@{
                customerId        = '11111111-1111-1111-1111-111111111111'
                defaultDomainName = 'contoso.onmicrosoft.com'
                initialDomainName = 'contoso.onmicrosoft.com'
                displayName       = 'Contoso Ltd'
            }
        }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($Filter)
            if ($Filter -match "PartitionKey eq 'AllTenants'") { return $script:GlobalRows }
            return $script:TenantRows
        }
    }

    Context 'typed variables are written as JSON literals' {
        BeforeEach {
            $script:GlobalRows = @(
                New-VariableRow -Name 'lockseconds' -Value '300' -VariableType 'integer'
                New-VariableRow -Name 'requirepw' -Value 'true' -VariableType 'boolean'
                New-VariableRow -Name 'allowedapps' -Value '["word.exe","excel.exe"]' -VariableType 'json'
            )
        }

        It 'writes an integer variable as a number with -EscapeForJson' {
            $Result = Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text '{"v":"%lockseconds%"}' -EscapeForJson
            $Result | Should -Be '{"v":300}'
            ($Result | ConvertFrom-Json).v | Should -BeOfType [long]
        }

        It 'writes an integer variable as a number without -EscapeForJson' {
            # The declared type decides, so callers that never opted into JSON escaping still get the
            # correct literal.
            $Result = Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text '{"v":"%lockseconds%"}'
            $Result | Should -Be '{"v":300}'
        }

        It 'writes a boolean variable as true or false' {
            Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text '{"v":"%requirepw%"}' -EscapeForJson |
                Should -Be '{"v":true}'
            Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text '{"v":"%requirepw%"}' |
                Should -Be '{"v":true}'
        }

        It 'writes a json variable as structure' {
            $Result = Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text '{"v":"%allowedapps%"}' -EscapeForJson
            (Test-IsValidJson $Result) | Should -BeTrue
            @(($Result | ConvertFrom-Json).v) | Should -Be @('word.exe', 'excel.exe')
        }

        It 'only unquotes a variable that fills the whole slot' {
            # Embedded in a longer string the variable is still part of that string.
            $Result = Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text '{"v":"waits %lockseconds% seconds"}' -EscapeForJson
            $Result | Should -Be '{"v":"waits 300 seconds"}'
            ($Result | ConvertFrom-Json).v | Should -BeOfType [string]
        }
    }

    Context 'a value that does not match its declared type falls back to the quoted form' {
        BeforeEach {
            $script:GlobalRows = @(
                New-VariableRow -Name 'badint' -Value 'not-a-number' -VariableType 'integer'
                New-VariableRow -Name 'badbool' -Value 'maybe' -VariableType 'boolean'
                New-VariableRow -Name 'badjson' -Value '{not json' -VariableType 'json'
            )
        }

        It 'keeps the JSON valid rather than emitting a bare literal' {
            foreach ($Name in @('badint', 'badbool', 'badjson')) {
                # Braces doubled: -f treats a single brace as a format placeholder.
                $Result = Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text ('{{"v":"%{0}%"}}' -f $Name) -EscapeForJson
                (Test-IsValidJson $Result) | Should -BeTrue -Because "$Name should degrade to a quoted string"
                ($Result | ConvertFrom-Json).v | Should -BeOfType [string]
            }
        }
    }

    Context 'variables that predate typing are unaffected' {
        BeforeEach {
            # No VariableType property at all, and a value containing backslashes - the canonical
            # custom variable, per this function's own doc comment.
            $script:GlobalRows = @(
                New-VariableRow -Name 'wallpaperpath' -Value 'C:\Wallpapers\corp.png'
                New-VariableRow -Name 'sitecode' -Value 'FAB01'
            )
        }

        It 'escapes an untyped variable only when the caller asks for it' {
            Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text '{"v":"%wallpaperpath%"}' -EscapeForJson |
                Should -Be '{"v":"C:\\Wallpapers\\corp.png"}'

            # Unescaped is the pre-existing behaviour of the callers that do not pass the switch. It
            # produces invalid JSON, and this test pins that it is unchanged rather than endorsing it.
            Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text '{"v":"%wallpaperpath%"}' |
                Should -Be '{"v":"C:\Wallpapers\corp.png"}'
        }

        It 'never unquotes an untyped variable' {
            Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text '{"v":"%sitecode%"}' -EscapeForJson |
                Should -Be '{"v":"FAB01"}'
        }

        It 'substitutes into plain text unchanged' {
            Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text 'Copy from %wallpaperpath% now' |
                Should -Be 'Copy from C:\Wallpapers\corp.png now'
        }
    }

    Context 'a variable typed as string behaves exactly like an untyped one' {
        It 'produces identical output either way' {
            $script:GlobalRows = @(New-VariableRow -Name 'sitename' -Value 'Contoso "HQ"' -VariableType 'string')
            $Typed = Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text '{"v":"%sitename%"}' -EscapeForJson

            $script:GlobalRows = @(New-VariableRow -Name 'sitename' -Value 'Contoso "HQ"')
            $Untyped = Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text '{"v":"%sitename%"}' -EscapeForJson

            $Typed | Should -Be $Untyped
            (Test-IsValidJson $Typed) | Should -BeTrue
        }
    }

    Context 'scope and precedence' {
        It 'lets a tenant variable override a global one, type included' {
            $script:GlobalRows = @(New-VariableRow -Name 'timeout' -Value 'global-value')
            $script:TenantRows = @(New-VariableRow -Name 'timeout' -Value '900' -VariableType 'integer')

            Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text '{"v":"%timeout%"}' -EscapeForJson |
                Should -Be '{"v":900}'
        }

        It 'still replaces reserved variables' {
            Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text 'Welcome to %tenantname% (%tenantid%)' |
                Should -Be 'Welcome to Contoso Ltd (11111111-1111-1111-1111-111111111111)'
        }

        It 'returns non-string input untouched' {
            $Input = @{ a = 1 }
            Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text $Input | Should -Be $Input
        }

        It 'returns the text unchanged when there is no tenant context' {
            Get-CIPPTextReplacement -TenantFilter '' -Text 'Nothing %lockseconds% replaced' |
                Should -Be 'Nothing %lockseconds% replaced'
        }
    }

    Context 'built-in tokens honour -EscapeForJson' {
        BeforeEach {
            # A tenant display name is free text an operator typed into Partner Center. CIPP does not
            # control it, so it has to be escaped exactly like a custom variable is.
            Mock -CommandName Get-Tenants -MockWith {
                [pscustomobject]@{
                    customerId        = '11111111-1111-1111-1111-111111111111'
                    defaultDomainName = 'contoso.onmicrosoft.com'
                    initialDomainName = 'contoso.onmicrosoft.com'
                    displayName       = 'Contoso "HQ" \ Ltd'
                }
            }
        }

        It 'escapes a display name containing a quote and a backslash' {
            $Result = Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text '{"v":"%tenantname%"}' -EscapeForJson

            (Test-IsValidJson $Result) | Should -BeTrue
            ($Result | ConvertFrom-Json).v | Should -Be 'Contoso "HQ" \ Ltd'
        }

        It 'survives the round trip a caller performs on a whole document' {
            # This is Push-CIPPStandard's pattern: serialize, replace, reparse.
            $Document = [pscustomobject]@{ displayName = '%tenantname%'; domain = '%tenantfilter%' } | ConvertTo-Json -Compress
            $Replaced = Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text $Document -EscapeForJson

            { $Replaced | ConvertFrom-Json -ErrorAction Stop } | Should -Not -Throw
            ($Replaced | ConvertFrom-Json).displayName | Should -Be 'Contoso "HQ" \ Ltd'
        }

        It 'leaves a built-in token unescaped when the caller does not ask' {
            # Pinning the pre-existing behaviour of the callers that pass plain text, not JSON.
            Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text 'Welcome to %tenantname%' |
                Should -Be 'Welcome to Contoso "HQ" \ Ltd'
        }
    }

    Context 'replacement values are written literally' {
        It 'does not expand a regex substitution pattern in a custom variable' {
            # -replace reads its replacement as a substitution pattern, so an unescaped $& would be
            # replaced by the matched token rather than written out.
            $script:GlobalRows = @(New-VariableRow -Name 'adminpw' -Value 'P@ss$&word$1$$')

            Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text 'pw=%adminpw%' |
                Should -Be 'pw=P@ss$&word$1$$'
        }

        It 'does not expand a regex substitution pattern in a built-in token' {
            Mock -CommandName Get-Tenants -MockWith {
                [pscustomobject]@{
                    customerId        = '11111111-1111-1111-1111-111111111111'
                    defaultDomainName = 'contoso.onmicrosoft.com'
                    initialDomainName = 'contoso.onmicrosoft.com'
                    displayName       = 'Smith $& Sons'
                }
            }

            Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text 'Welcome to %tenantname%' |
                Should -Be 'Welcome to Smith $& Sons'
        }

        It 'keeps a dollar sign intact through JSON escaping' {
            $script:GlobalRows = @(New-VariableRow -Name 'sharepath' -Value '\\srv\share$\folder')

            $Result = Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text '{"v":"%sharepath%"}' -EscapeForJson

            (Test-IsValidJson $Result) | Should -BeTrue
            ($Result | ConvertFrom-Json).v | Should -Be '\\srv\share$\folder'
        }

        It 'does not expand a substitution pattern inside a json typed variable' {
            $script:GlobalRows = @(New-VariableRow -Name 'paths' -Value '["c:\\a$&b"]' -VariableType 'json')

            $Result = Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text '{"v":"%paths%"}' -EscapeForJson

            (Test-IsValidJson $Result) | Should -BeTrue
            @(($Result | ConvertFrom-Json).v) | Should -Be @('c:\a$&b')
        }
    }

    Context 'variable names are matched literally' {
        It 'does not treat a regex metacharacter in a name as a pattern' {
            $script:GlobalRows = @(New-VariableRow -Name 'app.exe' -Value 'winword.exe')

            # %appXexe% would match too if the name were used as a raw regex.
            Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text '%app.exe% and %appXexe%' |
                Should -Be 'winword.exe and %appXexe%'
        }

        It 'still replaces a name containing brackets' {
            $script:GlobalRows = @(New-VariableRow -Name 'drive[main]' -Value 'D:')

            Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text 'path=%drive[main]%\data' |
                Should -Be 'path=D:\data'
        }
    }

    Context 'the Intune template regression' {
        BeforeEach {
            # A logon banner reading 'property of "Contoso"'. Spliced in unescaped it closes the
            # string it lands in, which is what produced: unexpected character was encountered: O.
            $script:GlobalRows = @(
                New-VariableRow -Name 'endpointdisclaimertitle' -Value 'Authorised Use Only'
                New-VariableRow -Name 'endpointdisclaimermessagel1' -Value 'This system is the property of "Onelife Dermatology HB".'
            )
        }

        It 'keeps a policy payload parseable when a banner variable contains a quote' {
            # Set-CIPPIntunePolicy and Invoke-CIPPStandardIntuneTemplate both call this on RAWJson
            # directly, so the variable lands one level deep. That is the level -EscapeForJson is for.
            $RawJson = '{"settings":[{"value":"%endpointdisclaimertitle%"},{"value":"%endpointdisclaimermessagel1%"}]}'

            $Replaced = Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text $RawJson -EscapeForJson

            { $Replaced | ConvertFrom-Json -ErrorAction Stop } | Should -Not -Throw
            @(($Replaced | ConvertFrom-Json).settings.value)[1] |
                Should -Be 'This system is the property of "Onelife Dermatology HB".'
        }

        It 'produces the documented failure without the switch' {
            $RawJson = '{"settings":[{"value":"%endpointdisclaimermessagel1%"}]}'

            $Replaced = Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text $RawJson

            (Test-IsValidJson $Replaced) | Should -BeFalse -Because 'this is the bug the switch exists to prevent'
        }

        It 'escapes for one level of nesting only' {
            # Pins a real limit rather than a wish: a value is escaped for the document it is spliced
            # into, so a JSON document carried as a string inside that document needs a second pass
            # this function does not make. That is why Push-CIPPStandard drops the template picker's
            # rawData snapshot instead of trying to escape its way through it - see
            # Remove-CIPPStandardSettingsRawData.
            $Nested = [pscustomobject]@{
                RAWJson = '{"settings":[{"value":"%endpointdisclaimermessagel1%"}]}'
            } | ConvertTo-Json -Compress

            $Replaced = Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text $Nested -EscapeForJson

            # The outer document survives - the reparse Push-CIPPStandard performs no longer throws.
            { $Replaced | ConvertFrom-Json -ErrorAction Stop } | Should -Not -Throw
            # The inner one does not, which is why it must never reach this function nested.
            (Test-IsValidJson ($Replaced | ConvertFrom-Json).RAWJson) | Should -BeFalse
        }
    }

    Context 'reserved variables cannot be shadowed' {
        It 'leaves a Windows device token for the device to expand' {
            # An Intune template ships %SystemRoot% expecting Windows to resolve it on the endpoint.
            # A custom variable of the same name must not intercept it.
            $script:GlobalRows = @(New-VariableRow -Name 'systemroot' -Value 'C:\Hijacked')

            Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text 'path=%SystemRoot%\system32' |
                Should -Be 'path=%SystemRoot%\system32'
        }

        It 'applies the guard regardless of the case the variable was saved under' {
            $script:GlobalRows = @(New-VariableRow -Name 'SystemRoot' -Value 'C:\Hijacked')

            Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text 'path=%SystemRoot%\system32' |
                Should -Be 'path=%SystemRoot%\system32'
        }

        It 'protects every device token an Intune payload relies on' {
            $DeviceTokens = @(
                'serial', 'systemdrive', 'system32', 'osdrive', 'temp',
                'userprofile', 'username', 'userdomain', 'windir',
                'programfiles', 'programfiles(x86)', 'programdata'
            )
            foreach ($Token in $DeviceTokens) {
                $script:GlobalRows = @(New-VariableRow -Name $Token -Value 'HIJACKED')
                $Text = "value=%$Token%"

                Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text $Text |
                    Should -Be $Text -Because "%$Token% is reserved for the device"
            }
        }

        It 'still resolves a tenant token the guard lists' {
            # The guard stops a custom variable shadowing it; the built-in pass still fills it in.
            $script:GlobalRows = @(New-VariableRow -Name 'tenantname' -Value 'Shadowed')

            Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text 'Welcome to %tenantname%' |
                Should -Be 'Welcome to Contoso Ltd'
        }
    }

    Context 'lazily resolved tokens' {
        BeforeEach {
            $script:ConfigRow = [pscustomobject]@{ Value = 'https://cipp.contoso.com' }
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                param($Filter)
                if ($Filter -match 'InstanceProperties') { return $script:ConfigRow }
                if ($Filter -match "PartitionKey eq 'AllTenants'") { return $script:GlobalRows }
                return $script:TenantRows
            }
            Mock -CommandName Get-CIPPSchemaExtensions -MockWith {
                @(
                    [pscustomobject]@{ id = 'extABC_otherThing' }
                    [pscustomobject]@{ id = 'extABC_cippUser' }
                )
            }
        }

        It 'resolves %cippurl% from the Config table' {
            Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text 'Open %cippurl%/standards' |
                Should -Be 'Open https://cipp.contoso.com/standards'
        }

        It 'leaves %cippurl% alone when the instance has no URL recorded' {
            $script:ConfigRow = $null

            Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text 'Open %cippurl%' |
                Should -Be 'Open %cippurl%'
        }

        It 'resolves %cippuserschema% to the cippUser extension' {
            Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text 'schema=%cippuserschema%' |
                Should -Be 'schema=extABC_cippUser'
        }

        It 'does not look the schema up when the token is absent' {
            # The lookup is a Graph call, so it must stay behind the guard.
            Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text 'nothing to do here' | Out-Null

            Should -Invoke Get-CIPPSchemaExtensions -Times 0 -Exactly
        }

        It 'escapes a lazily resolved token for JSON as well' {
            $script:ConfigRow = [pscustomobject]@{ Value = 'https://cipp.contoso.com/a"b' }

            $Result = Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text '{"v":"%cippurl%"}' -EscapeForJson

            (Test-IsValidJson $Result) | Should -BeTrue
            ($Result | ConvertFrom-Json).v | Should -Be 'https://cipp.contoso.com/a"b'
        }
    }

    Context 'partner tokens' {
        BeforeEach {
            $script:OldTenantId = $env:TenantID
            $script:OldAppId = $env:ApplicationID
            $env:TenantID = 'partner-tenant-guid'
            $env:ApplicationID = 'sam-app-guid'
        }
        AfterEach {
            $env:TenantID = $script:OldTenantId
            $env:ApplicationID = $script:OldAppId
        }

        It 'resolves the partner tenant and SAM application ids' {
            Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text '%partnertenantid%/%samappid%' |
                Should -Be 'partner-tenant-guid/sam-app-guid'
        }
    }

    Context 'tenant scoping' {
        It 'falls back to the defaultDomainName partition when the customerId partition is empty' {
            # Rows written before the customerId convention are keyed on the domain name.
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                param($Filter)
                if ($Filter -match "PartitionKey eq 'AllTenants'") { return @() }
                if ($Filter -match "PartitionKey eq '11111111") { return @() }
                if ($Filter -match "PartitionKey eq 'contoso.onmicrosoft.com'") {
                    return @([pscustomobject]@{ RowKey = 'sitecode'; Value = 'LEGACY01' })
                }
                return @()
            }

            Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text 'site=%sitecode%' |
                Should -Be 'site=LEGACY01'
        }

        It 'resolves built-in tokens to empty when the tenant cannot be found' {
            Mock -CommandName Get-Tenants -MockWith { $null }

            Get-CIPPTextReplacement -TenantFilter 'ghost.onmicrosoft.com' -Text 'id=[%tenantid%]' |
                Should -Be 'id=[]'
        }
    }

    Context 'rows the table may hold' {
        It 'skips a row with no Value column instead of failing' {
            $script:GlobalRows = @(
                New-ValuelessRow -Name 'broken'
                New-VariableRow -Name 'sitecode' -Value 'FAB01'
            )

            Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text '%broken%/%sitecode%' |
                Should -Be '%broken%/FAB01'
        }

        It 'substitutes an empty value as empty' {
            $script:GlobalRows = @(New-VariableRow -Name 'suffix' -Value '')

            Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text 'name%suffix%end' |
                Should -Be 'nameend'
        }
    }

    Context 'awkward values survive JSON escaping' {
        It 'escapes newlines and tabs' {
            $Banner = "Line one`r`nLine two`tTabbed"
            $script:GlobalRows = @(New-VariableRow -Name 'banner' -Value $Banner)

            $Result = Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text '{"v":"%banner%"}' -EscapeForJson

            (Test-IsValidJson $Result) | Should -BeTrue
            ($Result | ConvertFrom-Json).v | Should -Be $Banner
        }

        It 'round-trips non-ASCII text' {
            $Value = 'Ærø - naive - 日本語 - emoji'
            $script:GlobalRows = @(New-VariableRow -Name 'sitename' -Value $Value)

            $Result = Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text '{"v":"%sitename%"}' -EscapeForJson

            (Test-IsValidJson $Result) | Should -BeTrue
            ($Result | ConvertFrom-Json).v | Should -Be $Value
        }

        It 'escapes a value that is itself a JSON document' {
            # An untyped variable holding JSON is still a string, so it has to be escaped as one.
            $script:GlobalRows = @(New-VariableRow -Name 'blob' -Value '{"a":1,"b":"two"}')

            $Result = Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text '{"v":"%blob%"}' -EscapeForJson

            (Test-IsValidJson $Result) | Should -BeTrue
            ($Result | ConvertFrom-Json).v | Should -Be '{"a":1,"b":"two"}'
        }

        It 'handles every awkward character at once' {
            $Value = "quote "" backslash \ tab`t newline`n dollar `$& brace `${x}"
            $script:GlobalRows = @(New-VariableRow -Name 'kitchen' -Value $Value)

            $Result = Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text '{"v":"%kitchen%"}' -EscapeForJson

            (Test-IsValidJson $Result) | Should -BeTrue
            ($Result | ConvertFrom-Json).v | Should -Be $Value
        }
    }

    Context 'multiple tokens in one document' {
        BeforeEach {
            $script:GlobalRows = @(
                New-VariableRow -Name 'sitecode' -Value 'FAB01'
                New-VariableRow -Name 'drive' -Value 'D:'
            )
        }

        It 'replaces every occurrence of the same token' {
            Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text '%sitecode%-%sitecode%-%sitecode%' |
                Should -Be 'FAB01-FAB01-FAB01'
        }

        It 'replaces adjacent tokens' {
            Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text '%drive%%sitecode%' |
                Should -Be 'D:FAB01'
        }

        It 'mixes custom and built-in tokens' {
            Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text '%sitecode%@%tenantfilter%' |
                Should -Be 'FAB01@contoso.onmicrosoft.com'
        }

        It 'matches a token whatever case the template used' {
            Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text 'site=%SiteCode%' |
                Should -Be 'site=FAB01'
        }
    }

    Context 'repeated resolution' {
        It 'is stable when the pipeline resolves the same text twice' {
            # Push-CIPPStandard resolves the settings, then the standard resolves its payload again.
            $script:GlobalRows = @(New-VariableRow -Name 'sitename' -Value 'Contoso "HQ"')

            $Once = Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text '{"v":"%sitename%"}' -EscapeForJson
            $Twice = Get-CIPPTextReplacement -TenantFilter 'contoso.onmicrosoft.com' -Text $Once -EscapeForJson

            $Twice | Should -Be $Once
            ($Twice | ConvertFrom-Json).v | Should -Be 'Contoso "HQ"'
        }
    }
}
