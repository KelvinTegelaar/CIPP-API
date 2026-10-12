BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'New-CIPPOneDriveShortCut.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate New-CIPPOneDriveShortCut.ps1 under Modules/' }

    function Get-CIPPSPOTenant { param($TenantFilter) }
    function New-GraphGetRequest { param($uri, $tenantid, $asapp) }
    function New-GraphPOSTRequest { param($uri, $body, $type, $tenantid, $asapp) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$($Exception.Exception.Message)" } }
    . $FunctionPath
}

Describe 'New-CIPPOneDriveShortCut shortcut name' {
    BeforeEach {
        Mock Get-CIPPSPOTenant { [pscustomobject]@{ DisableAddToOneDrive = $false } }
        Mock Write-LogMessage { }
        Mock New-GraphPOSTRequest { if ($type -ne 'PATCH') { [pscustomobject]@{ id = 'new1'; name = 'Sales - Documents' } } }
        Mock New-GraphGetRequest {
            if ($uri -match '/drives\?') { return @([pscustomobject]@{ id = 'd1'; name = 'Documents'; webUrl = 'https://contoso.sharepoint.com/sites/Sales/Shared Documents' }) }
            if ($uri -match '/drives/d1/root\?') { return [pscustomobject]@{ id = 'item1'; name = 'root' } }
            [pscustomobject]@{ id = 's1'; displayName = 'Sales'; webUrl = 'https://contoso.sharepoint.com/sites/Sales' }
        }
    }

    BeforeAll {
        function Invoke-Shortcut {
            param($Name, $Url = 'https://contoso.sharepoint.com/sites/Sales/Shared Documents')
            New-CIPPOneDriveShortCut -Username 'a@contoso.com' -UserId 'u1' -URL $Url -TenantFilter 'contoso.com' -ShortcutName $Name
        }
    }

    It 'uses the custom name as the body name and in the result' {
        $Result = Invoke-Shortcut -Name 'Team Docs'
        $Result | Should -Match 'called Team Docs in'
        Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter { ($body | ConvertFrom-Json).name -eq 'Team Docs' }
    }

    It 'uses the custom name for a site-root shortcut' {
        $null = Invoke-Shortcut -Name 'Sales Site' -Url 'https://contoso.sharepoint.com/sites/Sales'
        Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter { ($body | ConvertFrom-Json).name -eq 'Sales Site' }
    }

    It 'keeps the derived name when blank or whitespace' {
        foreach ($Blank in @($null, '', '   ')) {
            $Result = Invoke-Shortcut -Name $Blank
            $Result | Should -Match 'called Sales - Documents in'
        }
        Should -Invoke New-GraphPOSTRequest -Times 3 -ParameterFilter { ($body | ConvertFrom-Json).name -eq 'Documents' }
    }

    It 'rejects <Why> without calling Graph' -ForEach @(
        @{ Why = 'a forbidden character'; Name = 'a:b'; Match = 'cannot contain' }
        @{ Why = 'a quote'; Name = 'a"b'; Match = 'cannot contain' }
        @{ Why = 'a backslash'; Name = 'a\b'; Match = 'cannot contain' }
        @{ Why = 'a slash'; Name = 'a/b'; Match = 'cannot contain' }
        @{ Why = 'a pipe'; Name = 'a|b'; Match = 'cannot contain' }
        @{ Why = 'an asterisk'; Name = 'a*b'; Match = 'cannot contain' }
        @{ Why = 'a question mark'; Name = 'a?b'; Match = 'cannot contain' }
        @{ Why = 'angle brackets'; Name = 'a<b>'; Match = 'cannot contain' }
        @{ Why = 'a leading space'; Name = ' ab'; Match = 'start or end with a space' }
        @{ Why = 'a trailing space'; Name = 'ab '; Match = 'start or end with a space' }
        @{ Why = 'a trailing period'; Name = 'ab.'; Match = 'end with a period' }
        @{ Why = '256 characters'; Name = ('a' * 256); Match = '255 characters' }
    ) {
        { Invoke-Shortcut -Name $Name } | Should -Throw "*$Match*"
        Should -Invoke New-GraphPOSTRequest -Times 0
        Should -Invoke New-GraphGetRequest -Times 0
    }

    It 'accepts a 255 character name and a mid-name period' {
        { Invoke-Shortcut -Name ('a' * 255) } | Should -Not -Throw
        { Invoke-Shortcut -Name 'v1.2 docs' } | Should -Not -Throw
    }

    Context 'rename after create' {
        It 'PATCHes the created item when OneDrive changed the name' {
            $Result = Invoke-Shortcut -Name 'Team Docs'
            Should -Invoke New-GraphPOSTRequest -Times 1 -ParameterFilter {
                $type -eq 'PATCH' -and $uri -match '/users/a@contoso.com/drive/items/new1$' -and ($body | ConvertFrom-Json).name -eq 'Team Docs'
            }
            $Result | Should -Match 'called Team Docs in'
        }

        It 'does not PATCH when the created name already matches' {
            Mock New-GraphPOSTRequest { if ($type -ne 'PATCH') { [pscustomobject]@{ id = 'new1'; name = 'Team Docs' } } }
            $null = Invoke-Shortcut -Name 'Team Docs'
            Should -Invoke New-GraphPOSTRequest -Times 0 -ParameterFilter { $type -eq 'PATCH' }
        }

        It 'does not PATCH for a blank name and reports the name OneDrive stored' {
            $Result = Invoke-Shortcut -Name ''
            Should -Invoke New-GraphPOSTRequest -Times 0 -ParameterFilter { $type -eq 'PATCH' }
            $Result | Should -Match 'called Sales - Documents in'
        }

        It 'keeps the shortcut and warns when the rename fails' {
            Mock New-GraphPOSTRequest { if ($type -eq 'PATCH') { throw 'nameAlreadyExists' } else { [pscustomobject]@{ id = 'new1'; name = 'Sales - Documents' } } }
            $Result = $null
            { $script:Result = Invoke-Shortcut -Name 'Team Docs' } | Should -Not -Throw
            $script:Result | Should -Match 'called Sales - Documents in.*renaming it to Team Docs failed: nameAlreadyExists'
            Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $Sev -eq 'Warning' }
        }
    }
}
