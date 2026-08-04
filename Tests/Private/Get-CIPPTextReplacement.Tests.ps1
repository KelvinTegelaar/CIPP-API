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
}
