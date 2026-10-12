# Pester tests for the CIPPPwPush module and the CippExtensions PWPush wrappers built on it.

BeforeAll {
    $ModulesRoot = "$PSScriptRoot/../../Modules"
    Add-Type -Path "$PSScriptRoot/../../Shared/CIPPSharp/bin/CIPPSharp.dll" -ErrorAction SilentlyContinue
    $script:PwPushFiles = @(
        Get-ChildItem "$ModulesRoot/CIPPPwPush/Public", "$ModulesRoot/CIPPPwPush/Private" -Filter '*.ps1' -Recurse
        Get-ChildItem "$ModulesRoot/CippExtensions/Public/PwPush", "$ModulesRoot/CippExtensions/Private/PwPush" -Filter '*.ps1'
    )
    foreach ($File in $script:PwPushFiles) { . $File.FullName }

    function Invoke-CIPPRestMethod { [CmdletBinding()] param($Uri, $Method = 'GET', $Body, $Headers, $ContentType, [int]$TimeoutSec, [int]$MaximumRedirection = -1) }
    function Write-LogMessage { param($API, $Message, $Sev, $LogData, $tenant, $headers) }
    function Get-CippException { param($Exception) [pscustomobject]@{ Message = $Exception.Exception.Message } }
    function Get-CIPPTable { param($TableName) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Get-ExtensionAPIKey { param($Extension) $script:Secrets[$Extension] }

    function New-HttpError([int]$Status, [hashtable]$Headers = @{}, [string]$Content = '') {
        $Dictionary = [System.Collections.Generic.Dictionary[string, string[]]]::new()
        foreach ($Key in $Headers.Keys) { $Dictionary[$Key] = @("$($Headers[$Key])") }
        [CIPP.CIPPHttpRequestException]::new("Response status code does not indicate success: $Status", $Status, $Dictionary, $Content)
    }

    function Set-TestPwPushConfig([hashtable]$PWPush, [hashtable]$CFZTNA = @{ Enabled = $false }) {
        $script:ConfigJson = @{ PWPush = $PWPush; CFZTNA = $CFZTNA } | ConvertTo-Json -Depth 5
    }

    $script:V1 = [pscustomobject]@{ BaseUrl = 'https://push.example'; ApiVersion = 'v1'; Headers = @{ Accept = 'application/json' } }
    $script:V2 = [pscustomobject]@{ BaseUrl = 'https://push.example'; ApiVersion = 'v2'; Headers = @{ Accept = 'application/json' } }
}

Describe 'CIPPPwPush' {
    BeforeEach {
        $script:Calls = [System.Collections.Generic.List[object]]::new()
        # Queue of responses for API calls; an exception entry is thrown, anything else returned
        $script:Queue = [System.Collections.Generic.Queue[object]]::new()
        $script:VersionResponse = $null
        $script:Secrets = @{ PWPush = 'pester-token'; CFZTNA = 'pester-cf-secret' }
        $script:ConfigJson = $null
        if ($script:CIPPPwPushVersionCache) { $script:CIPPPwPushVersionCache.Clear() }

        Mock Start-Sleep {}
        Mock Write-LogMessage {}
        Mock Get-CIPPAzDataTableEntity { if ($script:ConfigJson) { [pscustomobject]@{ config = $script:ConfigJson } } }
        Mock Invoke-CIPPRestMethod {
            $script:Calls.Add([pscustomobject]@{ Uri = "$Uri"; Method = "$Method"; Headers = $Headers; Body = $Body; ContentType = $ContentType; MaximumRedirection = $MaximumRedirection })
            $Next = if ("$Uri" -like '*/api/v2/version') { $script:VersionResponse } else { $script:Queue.Dequeue() }
            if ($Next -is [Exception]) { throw $Next }
            $Next
        }
    }

    Describe 'New-CIPPPwPush' {
        It 'posts a v1 push to /p.json with the password wrapper and account_id at the top level' {
            $script:Queue.Enqueue([pscustomobject]@{ url_token = 'tok1'; html_url = 'https://push.example/p/tok1' })

            $Result = New-CIPPPwPush -Connection $script:V1 -Payload 'S3cret!' -ExpireAfterDays 3 -WorkspaceId '123'

            $script:Calls.Count | Should -Be 1
            $script:Calls[0].Uri | Should -Be 'https://push.example/p.json'
            $script:Calls[0].Method | Should -Be 'POST'
            $script:Calls[0].ContentType | Should -Be 'application/json'
            $script:Calls[0].Body | Should -BeOfType [string]
            $script:Calls[0].Body | Should -BeLike '*"account_id":"123"*'
            $Sent = $script:Calls[0].Body | ConvertFrom-Json -AsHashtable
            $Sent.Keys | Sort-Object | Should -Be @('account_id', 'password')
            $Sent.password.Keys | Sort-Object | Should -Be @('deletable_by_viewer', 'expire_after_days', 'kind', 'payload', 'retrieval_step')
            $Sent.password.retrieval_step | Should -BeExactly $false
            $Sent.password.deletable_by_viewer | Should -BeExactly $false
            $Sent.password.payload | Should -Be 'S3cret!'
            $Result.Link | Should -Be 'https://push.example/p/tok1'
            $Result.UrlToken | Should -Be 'tok1'
        }

        It 'posts a v2 push to /api/v2/pushes with the push wrapper and workspace_id at the top level' {
            $script:Queue.Enqueue([pscustomobject]@{ url_token = 'tok2'; html_url = 'https://links.example/p/tok2/r' })

            $Result = New-CIPPPwPush -Connection $script:V2 -Payload 'S3cret!' -ExpireAfterDays 7 -ExpireAfterViews 5 -DeletableByViewer $true -RetrievalStep $true -Passphrase 'pp' -WorkspaceId 'acct_oxQdpMWVm'

            $script:Calls[0].Uri | Should -Be 'https://push.example/api/v2/pushes'
            $Sent = $script:Calls[0].Body | ConvertFrom-Json -AsHashtable
            $Sent.Keys | Sort-Object | Should -Be @('push', 'workspace_id')
            $Sent.workspace_id | Should -Be 'acct_oxQdpMWVm'
            $Sent.push.Keys | Sort-Object | Should -Be @('deletable_by_viewer', 'expire_after_days', 'expire_after_views', 'kind', 'passphrase', 'payload', 'retrieval_step')
            $Sent.push.retrieval_step | Should -BeExactly $true
            $Sent.push.deletable_by_viewer | Should -BeExactly $true
            $Sent.push.Contains('expire_after_duration') | Should -BeFalse
            $Result.Link | Should -Be 'https://links.example/p/tok2/r'
        }

        It 'always sends retrieval_step and deletable_by_viewer under either wrapper' -ForEach @(
            @{ Version = 'v1'; Wrapper = 'password'; On = $true }
            @{ Version = 'v1'; Wrapper = 'password'; On = $false }
            @{ Version = 'v2'; Wrapper = 'push'; On = $true }
            @{ Version = 'v2'; Wrapper = 'push'; On = $false }
        ) {
            $script:Queue.Enqueue([pscustomobject]@{ html_url = 'https://push.example/p/x' })
            $Connection = if ($Version -eq 'v2') { $script:V2 } else { $script:V1 }
            $null = New-CIPPPwPush -Connection $Connection -Payload 'x' -RetrievalStep $On -DeletableByViewer $On
            $Inner = ($script:Calls[0].Body | ConvertFrom-Json -AsHashtable)[$Wrapper]
            $Inner.Contains('retrieval_step') | Should -BeTrue
            $Inner.Contains('deletable_by_viewer') | Should -BeTrue
            $Inner.retrieval_step | Should -BeExactly $On
            $Inner.deletable_by_viewer | Should -BeExactly $On
        }

        It 'sends no workspace id when none is given' {
            $script:Queue.Enqueue([pscustomobject]@{ html_url = 'https://push.example/p/x' })
            $null = New-CIPPPwPush -Connection $script:V2 -Payload 'x'
            ($script:Calls[0].Body | ConvertFrom-Json -AsHashtable).Keys | Should -Be @('push')
        }

        It 'builds the link from url_token when html_url is missing' {
            $script:Queue.Enqueue([pscustomobject]@{ url_token = 'tok3' })
            (New-CIPPPwPush -Connection $script:V1 -Payload 'x' -RetrievalStep $true).Link | Should -Be 'https://push.example/p/tok3/r'
            $script:Queue.Enqueue([pscustomobject]@{ url_token = 'tok4' })
            (New-CIPPPwPush -Connection $script:V1 -Payload 'x').Link | Should -Be 'https://push.example/p/tok4'
        }

        It 'throws when the response has no link' {
            $script:Queue.Enqueue([pscustomobject]@{ payload = 'echoed' })
            { New-CIPPPwPush -Connection $script:V1 -Payload 'x' } | Should -Throw 'PWPush API response did not contain a link'
        }

        It 'refuses to follow a redirect and names the target host' {
            $script:Queue.Enqueue((New-HttpError 301 @{ Location = 'https://eu.pwpush.com/p.json' }))

            { New-CIPPPwPush -Connection $script:V1 -Payload 'x' } | Should -Throw 'PWPush URL redirects to https://eu.pwpush.com - set that as the PWPush URL.'
            $script:Calls.Count | Should -Be 1
            $script:Calls[0].MaximumRedirection | Should -Be 0
        }

        It 'retries a 429 after the Retry-After delay and then succeeds' {
            $script:Queue.Enqueue((New-HttpError 429 @{ 'Retry-After' = '5' }))
            $script:Queue.Enqueue([pscustomobject]@{ html_url = 'https://push.example/p/ok' })

            (New-CIPPPwPush -Connection $script:V1 -Payload 'x').Link | Should -Be 'https://push.example/p/ok'
            $script:Calls.Count | Should -Be 2
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 5 }
        }

        It 'gives up after three attempts, backing off 2s then 4s without Retry-After' {
            1..3 | ForEach-Object { $script:Queue.Enqueue((New-HttpError 429)) }

            { New-CIPPPwPush -Connection $script:V1 -Payload 'x' } | Should -Throw 'PWPush API returned HTTP 429*'
            $script:Calls.Count | Should -Be 3
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 2 }
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 4 }
        }

        It 'does not retry other failures and keeps the response body out of the error' {
            $script:Queue.Enqueue((New-HttpError 422 @{} '{"payload":["S3cret! is too long"]}'))

            $Message = try { New-CIPPPwPush -Connection $script:V1 -Payload 'S3cret!'; $null } catch { $_.Exception.Message }
            $Message | Should -Be 'PWPush API returned HTTP 422 (payload)'
            $script:Calls.Count | Should -Be 1
        }
    }

    Describe 'Get-CIPPPwPushVersion' {
        It 'detects v2 with its edition and features, probing anonymously' {
            $script:VersionResponse = [pscustomobject]@{ api_version = '2.1'; edition = 'commercial'; features = [pscustomobject]@{ accounts = @{ enabled = $true } } }

            $Version = Get-CIPPPwPushVersion -BaseUrl 'https://push.example/ ' -Headers @{ 'CF-Access-Client-Id' = 'id' }

            $Version.ApiVersion | Should -Be 'v2'
            $Version.Edition | Should -Be 'commercial'
            $Version.Features.accounts.enabled | Should -BeTrue
            $script:Calls[0].Uri | Should -Be 'https://push.example/api/v2/version'
            $script:Calls[0].Headers.ContainsKey('Authorization') | Should -BeFalse
            $script:Calls[0].Headers['CF-Access-Client-Id'] | Should -Be 'id'
        }

        It 'falls back to v1 on 404' {
            $script:VersionResponse = New-HttpError 404
            (Get-CIPPPwPushVersion -BaseUrl 'https://oss.example').ApiVersion | Should -Be 'v1'
        }

        It 'remembers a result per base URL' {
            $script:VersionResponse = [pscustomobject]@{ api_version = '2.1'; edition = 'oss' }
            $null = Get-CIPPPwPushVersion -BaseUrl 'https://a.example'
            $null = Get-CIPPPwPushVersion -BaseUrl 'https://a.example/'
            $script:Calls.Count | Should -Be 1

            $script:VersionResponse = New-HttpError 404
            (Get-CIPPPwPushVersion -BaseUrl 'https://b.example').ApiVersion | Should -Be 'v1'
            $script:Calls.Count | Should -Be 2
        }

        It 'does not remember an inconclusive probe' {
            $script:VersionResponse = New-HttpError 503
            (Get-CIPPPwPushVersion -BaseUrl 'https://flaky.example').ApiVersion | Should -Be 'v1'
            $null = Get-CIPPPwPushVersion -BaseUrl 'https://flaky.example'
            $script:Calls.Count | Should -Be 2
        }
    }

    Describe 'Get-CIPPPwPushWorkspace' {
        It 'lists v2 workspaces with string ids' {
            $script:Queue.Enqueue(@([pscustomobject]@{ id = 'acct_a'; name = 'A' }, [pscustomobject]@{ id = 42; name = 'Legacy' }))

            $Workspaces = @(Get-CIPPPwPushWorkspace -Connection $script:V2)

            $script:Calls[0].Uri | Should -Be 'https://push.example/api/v2/workspaces'
            $Workspaces.id | Should -Be @('acct_a', '42')
            $Workspaces[1].id | Should -BeOfType [string]
        }

        It 'uses /api/v1/accounts on v1 and unwraps a wrapped list' {
            $script:Queue.Enqueue([pscustomobject]@{ accounts = @([pscustomobject]@{ id = 'acct_b'; name = 'B' }) })

            $Workspaces = @(Get-CIPPPwPushWorkspace -Connection $script:V1)

            $script:Calls[0].Uri | Should -Be 'https://push.example/api/v1/accounts'
            $Workspaces.name | Should -Be 'B'
        }
    }

    Describe 'New-PwPushConnection' {
        BeforeEach { $script:VersionResponse = [pscustomobject]@{ api_version = '2.1'; edition = 'commercial' } }

        It 'sends no Authorization header when no token is configured' {
            $Connection = New-PwPushConnection -Configuration ([pscustomobject]@{ BaseUrl = ' https://push.example/ ' })
            $Connection.BaseUrl | Should -Be 'https://push.example'
            $Connection.ApiVersion | Should -Be 'v2'
            $Connection.Headers.ContainsKey('Authorization') | Should -BeFalse
            $Connection.Headers['Accept'] | Should -Be 'application/json'
        }

        It 'sends no Authorization header when bearer auth is on but no key is stored' {
            $script:Secrets.PWPush = $null
            $Connection = New-PwPushConnection -Configuration ([pscustomobject]@{ BaseUrl = 'https://push.example'; UseBearerAuth = $true })
            $Connection.Headers.ContainsKey('Authorization') | Should -BeFalse
        }

        It 'sends a Bearer token when bearer auth is on' {
            $Connection = New-PwPushConnection -Configuration ([pscustomobject]@{ BaseUrl = 'https://push.example'; UseBearerAuth = $true })
            $Connection.Headers['Authorization'] | Should -Be 'Bearer pester-token'
            $script:Calls[0].Headers.ContainsKey('Authorization') | Should -BeFalse
        }

        It 'uses the key as a Bearer token for legacy email configs' {
            $Connection = New-PwPushConnection -Configuration ([pscustomobject]@{ BaseUrl = 'https://push.example'; EmailAddress = 'a@b.c' })
            $Connection.Headers['Authorization'] | Should -Be 'Bearer pester-token'
            $Connection.Headers.Keys | Should -Not -Contain 'X-User-Email'
        }

        It 'adds Cloudflare Access headers only when both switches are on' -ForEach @(
            @{ CFEnabled = $true; ZtnaEnabled = $true; Expected = $true }
            @{ CFEnabled = $true; ZtnaEnabled = $false; Expected = $false }
            @{ CFEnabled = $false; ZtnaEnabled = $true; Expected = $false }
        ) {
            $Full = [pscustomobject]@{ CFZTNA = [pscustomobject]@{ Enabled = $ZtnaEnabled; ClientId = 'cf-id' } }
            $Connection = New-PwPushConnection -Configuration ([pscustomobject]@{ BaseUrl = 'https://push.example'; CFEnabled = $CFEnabled }) -FullConfiguration $Full
            $Connection.Headers.ContainsKey('CF-Access-Client-Id') | Should -Be $Expected
            if ($Expected) {
                $Connection.Headers['CF-Access-Client-Id'] | Should -Be 'cf-id'
                $Connection.Headers['CF-Access-Client-Secret'] | Should -Be 'pester-cf-secret'
                $script:Calls[0].Headers['CF-Access-Client-Secret'] | Should -Be 'pester-cf-secret'
            }
        }
    }

    Describe 'New-PwPushLink' {
        BeforeEach { $script:VersionResponse = New-HttpError 404 }

        It 'returns $false when PWPush is unconfigured or disabled' {
            New-PwPushLink -Payload 'x' | Should -BeFalse
            Set-TestPwPushConfig @{ Enabled = $false; BaseUrl = 'https://push.example' }
            New-PwPushLink -Payload 'x' | Should -BeFalse
            $script:Calls.Count | Should -Be 0
        }

        It 'returns the link' {
            Set-TestPwPushConfig @{ Enabled = $true; BaseUrl = 'https://push.example'; RetrievalStep = $true }
            $script:Queue.Enqueue([pscustomobject]@{ url_token = 't'; html_url = 'https://push.example/p/t/r' })

            New-PwPushLink -Payload 'x' | Should -Be 'https://push.example/p/t/r'
            ($script:Calls[-1].Body | ConvertFrom-Json).password.retrieval_step | Should -BeTrue

            Set-TestPwPushConfig @{ Enabled = $true; BaseUrl = 'https://push.example'; RetrievalStep = $false }
            $script:Queue.Enqueue([pscustomobject]@{ url_token = 't'; html_url = 'https://push.example/p/t' })
            $null = New-PwPushLink -Payload 'x'
            $Sent = ($script:Calls[-1].Body | ConvertFrom-Json -AsHashtable).password
            $Sent.retrieval_step | Should -BeExactly $false
            $Sent.deletable_by_viewer | Should -BeExactly $false
        }

        It 'returns $false on failure and rethrows with -ThrowOnError' {
            Set-TestPwPushConfig @{ Enabled = $true; BaseUrl = 'https://push.example' }
            $script:Queue.Enqueue((New-HttpError 401))
            New-PwPushLink -Payload 'x' | Should -BeFalse
            Should -Invoke Write-LogMessage -ParameterFilter { $Sev -eq 'Error' }

            $script:Queue.Enqueue((New-HttpError 401))
            { New-PwPushLink -Payload 'x' -ThrowOnError } | Should -Throw '*HTTP 401*'
        }

        It 'omits out-of-range expiry settings with a warning' {
            Set-TestPwPushConfig @{ Enabled = $true; BaseUrl = 'https://push.example'; ExpireAfterDays = 365; ExpireAfterViews = 500 }
            $script:Queue.Enqueue([pscustomobject]@{ html_url = 'https://push.example/p/t' })

            New-PwPushLink -Payload 'x' | Should -Be 'https://push.example/p/t'
            $Sent = ($script:Calls[-1].Body | ConvertFrom-Json -AsHashtable).password
            $Sent.Contains('expire_after_days') | Should -BeFalse
            $Sent.Contains('expire_after_views') | Should -BeFalse
            Should -Invoke Write-LogMessage -Times 2 -Exactly -ParameterFilter { $Sev -eq 'Warning' -and $Message -like 'Ignoring ExpireAfter*' }
        }

        It 'passes the saved account id only with bearer auth' {
            Set-TestPwPushConfig @{ Enabled = $true; BaseUrl = 'https://push.example'; UseBearerAuth = $false; AccountId = @{ value = 'acct_x' } }
            $script:Queue.Enqueue([pscustomobject]@{ html_url = 'https://push.example/p/t' })
            $null = New-PwPushLink -Payload 'x'
            ($script:Calls[-1].Body | ConvertFrom-Json -AsHashtable).Contains('account_id') | Should -BeFalse

            Set-TestPwPushConfig @{ Enabled = $true; BaseUrl = 'https://push.example'; UseBearerAuth = $true; AccountId = @{ value = 'acct_x' } }
            $script:Queue.Enqueue([pscustomobject]@{ html_url = 'https://push.example/p/t' })
            $null = New-PwPushLink -Payload 'x'
            ($script:Calls[-1].Body | ConvertFrom-Json).account_id | Should -Be 'acct_x'
            $script:Calls[-1].Headers['Authorization'] | Should -Be 'Bearer pester-token'
        }
    }

    Describe 'Get-PwPushAccount' {
        BeforeEach { $script:VersionResponse = [pscustomobject]@{ api_version = '2.1'; edition = 'commercial' } }

        It 'returns the not-configured placeholder when disabled' {
            Set-TestPwPushConfig @{ Enabled = $true; UseBearerAuth = $false }
            $Rows = @(Get-PwPushAccount)
            $Rows.Count | Should -Be 1
            $Rows[0].name | Should -Be 'PWPush Pro is not enabled or configured. Make sure to save the configuration first.'
            $Rows[0].id | Should -Be ''
        }

        It 'returns the retrieval placeholder on failure or an empty list' -ForEach @(
            @{ Reply = { New-HttpError 401 } }
            @{ Reply = { , @() } }
        ) {
            Set-TestPwPushConfig @{ Enabled = $true; UseBearerAuth = $true; BaseUrl = 'https://push.example' }
            $script:Queue.Enqueue((& $Reply))
            $Rows = @(Get-PwPushAccount)
            $Rows.Count | Should -Be 1
            $Rows[0].name | Should -BeLike 'Could not retrieve accounts.*'
        }

        It 'returns normalised accounts with string ids' {
            Set-TestPwPushConfig @{ Enabled = $true; UseBearerAuth = $true; BaseUrl = 'https://push.example' }
            $script:Queue.Enqueue(@([pscustomobject]@{ id = 'acct_a'; name = 'A'; created_at = 'x' }, [pscustomobject]@{ id = 7; name = 'B' }))

            $Rows = @(Get-PwPushAccount)
            $Rows.id | Should -Be @('acct_a', '7')
            $Rows.name | Should -Be @('A', 'B')
            $script:Calls[-1].Uri | Should -Be 'https://push.example/api/v2/workspaces'
        }
    }

    Describe 'Call sites' {
        It 'only pass parameters the PWPush functions accept' {
            $Commands = @{}
            foreach ($Name in 'New-PwPushLink', 'Get-PwPushAccount', 'New-PwPushConnection', 'New-CIPPPwPush', 'Get-CIPPPwPushWorkspace', 'Get-CIPPPwPushVersion', 'Invoke-CIPPPwPushRequest') {
                $Commands[$Name] = Get-Command $Name -CommandType Function
            }
            $Pattern = ($Commands.Keys | ForEach-Object { [regex]::Escape($_) }) -join '|'
            $SourceRoots = 'CippExtensions', 'CIPPHTTP', 'CIPPCore', 'CIPPPwPush' | ForEach-Object { "$PSScriptRoot/../../Modules/$_" }
            $Files = Get-ChildItem $SourceRoots -Filter '*.ps1' -Recurse | Select-String -Pattern $Pattern -List | ForEach-Object Path
            $Files.Count | Should -BeGreaterThan 9

            $Problems = foreach ($File in Get-Item $Files) {
                $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$null)
                foreach ($Call in $Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                    $Name = $Call.GetCommandName()
                    if (-not $Name -or -not $Commands.ContainsKey($Name)) { continue }
                    foreach ($Parameter in $Call.CommandElements.Where({ $_ -is [System.Management.Automation.Language.CommandParameterAst] })) {
                        try { $null = $Commands[$Name].ResolveParameter($Parameter.ParameterName) } catch { '{0}:{1} {2} -{3}' -f $File.Name, $Call.Extent.StartLineNumber, $Name, $Parameter.ParameterName }
                    }
                }
            }

            $Problems | Should -BeNullOrEmpty
        }

        It 'leaves no reference to the removed PassPushPosh module' {
            $Roots = "$PSScriptRoot/../../Modules", "$PSScriptRoot/../../../build"
            $Hits = Get-ChildItem $Roots -File -Recurse -Include '*.ps1', '*.psm1', '*.psd1', 'Dockerfile*', '*.yml', '*.json' -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -notmatch '[\\/]\.dev(modules|manifests)[\\/]' } |
                Select-String -Pattern 'PassPushPosh|Set-PwPushConfig|Get-PushAccount' -List
            $Hits | Should -BeNullOrEmpty
        }
    }
}
