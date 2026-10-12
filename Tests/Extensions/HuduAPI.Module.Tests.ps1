# Pins the vendored HuduAPI module behaviour CIPP relies on, so a module bump that changes it fails here
BeforeAll {
    $ModuleManifest = Get-ChildItem "$PSScriptRoot/../../Modules/HuduAPI" -Filter 'HuduAPI.psd1' -Recurse | Select-Object -First 1
    Import-Module $ModuleManifest.FullName -Force
    . "$PSScriptRoot/../../Modules/CippExtensions/Public/Hudu/Connect-HuduAPI.ps1"
    $script:ApiKey = 'pester-hudu-key-0123456789'
    $script:Configuration = [pscustomobject]@{
        Hudu   = [pscustomobject]@{ BaseURL = 'https://pester.huducloud.com'; CFEnabled = $false }
        CFZTNA = [pscustomobject]@{ Enabled = $true; ClientId = 'pester-client' }
    }

    function Get-ExtensionAPIKey { param($Extension) if ($Extension -eq 'CFZTNA') { 'pester-cf-secret' } else { $script:ApiKey } }

    function Get-RecordedCall([string]$Method, [string]$Path) {
        @($script:Calls | Where-Object { $_.Method -eq $Method -and $_.Path -eq $Path })
    }
}

AfterAll {
    Remove-Module HuduAPI -Force -ErrorAction SilentlyContinue
}

Describe 'CIPP call sites' {
    It 'only pass parameters the module accepts' {
        $HuduCommands = @{}
        foreach ($Command in Get-Command -Module HuduAPI) { $HuduCommands[$Command.Name] = $Command }

        $SourceRoots = 'CippExtensions', 'CIPPHTTP', 'CIPPCore' | ForEach-Object { "$PSScriptRoot/../../Modules/$_" }
        $Files = Get-ChildItem $SourceRoots -Filter '*.ps1' -Recurse | Select-String -Pattern '-Hudu' -List | ForEach-Object Path
        $Files | Should -Not -BeNullOrEmpty
        $Problems = foreach ($File in Get-Item $Files) {
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$null)
            foreach ($Call in $Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                $Name = $Call.GetCommandName()
                if (-not $Name -or -not $HuduCommands.ContainsKey($Name)) { continue }
                foreach ($Parameter in $Call.CommandElements.Where({ $_ -is [System.Management.Automation.Language.CommandParameterAst] })) {
                    try { $null = $HuduCommands[$Name].ResolveParameter($Parameter.ParameterName) } catch { '{0}:{1} {2} -{3}' -f $File.Name, $Call.Extent.StartLineNumber, $Name, $Parameter.ParameterName }
                }
            }
        }

        $Problems | Should -BeNullOrEmpty
    }
}

Describe 'HuduAPI requests' {
    BeforeEach {
        $script:Calls = [System.Collections.Generic.List[object]]::new()
        $script:FailWith = $null
        $script:RateLimitedCalls = 0

        Mock -ModuleName HuduAPI Start-Sleep {}
        Mock -ModuleName HuduAPI Set-Content {}
        Mock -ModuleName HuduAPI Invoke-RestMethod {
            $RequestUri = [uri]"$Uri"
            $script:Calls.Add([pscustomobject]@{
                    Method     = "$Method".ToUpper()
                    Path       = $RequestUri.AbsolutePath
                    Query      = [System.Web.HttpUtility]::ParseQueryString($RequestUri.Query)
                    Headers    = $Headers
                    Body       = $(if ($Body) { $Body | ConvertFrom-Json })
                    WebSession = $WebSession
                })
            if ($script:RateLimitedCalls -gt 0) { $script:RateLimitedCalls--; throw 'Retry later' }
            if ($script:FailWith) { throw $script:FailWith }

            switch -Regex ("$Method".ToUpper() + ' ' + $RequestUri.AbsolutePath) {
                '^GET /api/v1/api_info$' { [pscustomobject]@{ version = '2.46.1'; date = '2026-09-01' } }
                '^GET /api/v1/asset_layouts/(\d+)$' { [pscustomobject]@{ asset_layout = [pscustomobject]@{ id = [int]$Matches[1]; name = 'People'; fields = @() } } }
                '^GET /api/v1/assets$' {
                    $Count = if ($RequestUri.Query -match 'page=1(&|$)') { 1000 } else { 2 }
                    [pscustomobject]@{ assets = @(1..$Count | ForEach-Object { [pscustomobject]@{ id = $_ } }) }
                }
                '^(PUT|POST) ' { $Body | ConvertFrom-Json }
            }
        }

        Connect-HuduAPI -Configuration $script:Configuration
        $script:Calls.Clear()
    }

    It 'reuses one web session across requests' {
        $null = Get-HuduAppInfo
        $null = Get-HuduAppInfo

        $script:Calls.Count | Should -Be 2
        $script:Calls[0].WebSession | Should -BeOfType [Microsoft.PowerShell.Commands.WebRequestSession]
        [object]::ReferenceEquals($script:Calls[0].WebSession, $script:Calls[1].WebSession) | Should -BeTrue
        $script:Calls[0].Headers.'x-api-key' | Should -Be $script:ApiKey
    }

    It 'sends the Cloudflare Access headers on every request when enabled' {
        $script:Configuration.Hudu.CFEnabled = $true
        try {
            Connect-HuduAPI -Configuration $script:Configuration
            $null = Get-HuduAppInfo
            $script:Calls[-1].Headers.'CF-Access-Client-Id' | Should -Be 'pester-client'
            $script:Calls[-1].Headers.'CF-Access-Client-Secret' | Should -Be 'pester-cf-secret'
        } finally {
            $script:Configuration.Hudu.CFEnabled = $false
            InModuleScope HuduAPI { $Script:Int_HuduCustomHeaders = $null }
        }
    }

    Context 'when Hudu rejects the request' {
        BeforeEach { $script:FailWith = '{"error":"Bad credentials"}' }

        It 'returns nothing from Get-HuduAppInfo and leaves the reason as the last ErrorVariable record' {
            $HuduInfoErrors = $null
            $Version = Get-HuduAppInfo -ErrorAction SilentlyContinue -ErrorVariable HuduInfoErrors 3>$null

            $Version | Should -BeNullOrEmpty
            "$(@($HuduInfoErrors)[-1])" | Should -BeLike '*Bad credentials*'
        }

        It 'throws a message that parses back to the Hudu error body under -ErrorAction Stop' {
            $Message = try { Get-HuduAssetLayouts -ErrorAction Stop; $null } catch { $_.Exception.Message }

            ($Message -replace "'" | ConvertFrom-Json).error | Should -Be 'Bad credentials'
        }

        It 'does not retry a failed write' {
            { New-HuduRelation -FromableType 'Asset' -FromableID 1 -ToableType 'Asset' -ToableID 2 -ErrorAction Stop } | Should -Throw

            (Get-RecordedCall 'POST' '/api/v1/relations').Count | Should -Be 1
            Should -Invoke Start-Sleep -ModuleName HuduAPI -Times 0 -Exactly
        }

        It 'retries a failed read once after 5 seconds' {
            $null = Get-HuduAssetLayouts -ErrorAction SilentlyContinue

            (Get-RecordedCall 'GET' '/api/v1/asset_layouts').Count | Should -Be 2
            Should -Invoke Start-Sleep -ModuleName HuduAPI -Times 1 -Exactly -ParameterFilter { $Seconds -eq 5 }
        }

        It 'does not dump the request to the host or write error files to disk' {
            Mock -ModuleName HuduAPI Write-Host {}

            $null = Get-HuduAppInfo -ErrorAction SilentlyContinue -ErrorVariable HuduInfoErrors

            "$HuduInfoErrors" | Should -Not -Match ([regex]::Escape($script:ApiKey))
            Should -Invoke Write-Host -ModuleName HuduAPI -Times 0 -Exactly
            Should -Invoke Set-Content -ModuleName HuduAPI -Times 0 -Exactly
        }
    }

    It 'waits for the next 30 second window once and retries a rate-limited request' {
        Mock -ModuleName HuduAPI Get-Date { [datetime]'2026-10-05 10:07:10' }
        Mock -ModuleName HuduAPI Get-Random { 1 }
        $script:RateLimitedCalls = 1

        $Info = Get-HuduAppInfo

        $Info.version | Should -Be '2.46.1'
        $script:Calls.Count | Should -Be 2
        Should -Invoke Start-Sleep -ModuleName HuduAPI -Times 1 -Exactly -ParameterFilter { $Seconds -eq 21 }
    }

    It 'pages Get-HuduAssets until a short page' {
        $Assets = Get-HuduAssets -CompanyId 3 -AssetLayoutId 9

        $Assets.Count | Should -Be 1002
        $script:Calls.Count | Should -Be 2
        $script:Calls[0].Query['company_id'] | Should -Be '3'
        $script:Calls[0].Query['asset_layout_id'] | Should -Be '9'
    }

    Context 'Set-HuduAsset' {
        BeforeAll {
            $script:ExistingAsset = [pscustomobject]@{
                id = 7; name = 'Old'; company_id = 3; asset_layout_id = 9; slug = 'old'
                primary_serial = $null; primary_model = $null; primary_mail = $null; primary_manufacturer = $null
                fields = @([pscustomobject]@{ label = 'Microsoft 365'; value = 'old' })
            }
            $script:Fields = @(@{ microsoft_365 = 'new' })
        }

        It 'updates from -ExistingAsset without fetching the asset again' {
            $null = Set-HuduAsset -asset_id 7 -Name 'New' -company_id 3 -asset_layout_id 9 -Fields $script:Fields -PrimarySerial 'SER1' -ExistingAsset $script:ExistingAsset

            $script:Calls.Count | Should -Be 1
            $Put = Get-RecordedCall 'PUT' '/api/v1/companies/3/assets/7'
            $Put.Count | Should -Be 1
            $Put[0].Body.asset.name | Should -Be 'New'
            $Put[0].Body.asset.primary_serial | Should -Be 'SER1'
            $Put[0].Body.asset.custom_fields[0].microsoft_365 | Should -Be 'new'
        }

        It 'fetches the asset first when -ExistingAsset is not given' {
            Mock -ModuleName HuduAPI Get-HuduAssets { $script:ExistingAsset }

            $null = Set-HuduAsset -asset_id 7 -Name 'New' -company_id 3 -asset_layout_id 9 -Fields $script:Fields

            Should -Invoke Get-HuduAssets -ModuleName HuduAPI -Times 1 -Exactly -ParameterFilter { $Id -eq 7 }
            (Get-RecordedCall 'PUT' '/api/v1/companies/3/assets/7').Count | Should -Be 1
        }
    }

    It 'Set-HuduAssetLayout sends every field with its canonical field type' {
        $TypeMap = [ordered]@{
            text = 'Text'; richtext = 'RichText'; heading = 'Heading'; checkbox = 'CheckBox'; number = 'Number'; date = 'Date'
            dropdown = 'Dropdown'; embed = 'Embed'; phone = 'Phone'; email = 'Email'; copyabletext = 'Email'; assettag = 'AssetTag'
            assetlink = 'AssetTag'; website = 'Website'; link = 'Website'; password = 'Password'; confidentialtext = 'Password'
        }
        $Position = 0
        $Fields = foreach ($Type in $TypeMap.Keys) { @{ label = $Type; field_type = $Type; position = $Position++; show_in_list = 'true'; required = $false; expiration = $false } }

        $null = Set-HuduAssetLayout -Id 5 -Fields $Fields -ErrorAction Stop

        $Put = Get-RecordedCall 'PUT' '/api/v1/asset_layouts/5'
        $Put.Count | Should -Be 1
        $Sent = @{}
        foreach ($Field in $Put[0].Body.asset_layout.fields) { $Sent[$Field.label] = $Field }
        foreach ($Type in $TypeMap.Keys) {
            $Sent[$Type].field_type | Should -BeExactly $TypeMap[$Type]
            $Sent[$Type].show_in_list | Should -BeTrue
        }
    }

    It 'New-HuduRelation posts an Asset to Asset relation' {
        $null = New-HuduRelation -FromableType 'Asset' -FromableID 1 -ToableType 'Asset' -ToableID 2 -ErrorAction Stop

        $Post = Get-RecordedCall 'POST' '/api/v1/relations'
        $Post.Count | Should -Be 1
        $Post[0].Body.relation.fromable_type | Should -Be 'Asset'
        $Post[0].Body.relation.fromable_id | Should -Be 1
        $Post[0].Body.relation.toable_type | Should -Be 'Asset'
        $Post[0].Body.relation.toable_id | Should -Be 2
    }
}
