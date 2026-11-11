# Pester tests for the webhook channel's destination and header checks in Send-CIPPAlert.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $headers, $LogData) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    # A plain function, not a Mock: the status and header variables must land in the caller's scope.
    function Invoke-CIPPRestMethod {
        param($Uri, $Method, $Body, $Headers, $ContentType, $StatusCodeVariable, $ResponseHeadersVariable, [switch]$SkipHttpErrorCheck, $MaximumRedirection)
        $script:Sent.Add([pscustomobject]@{ Uri = $Uri; Method = $Method; Body = $Body; Headers = $Headers; MaximumRedirection = $MaximumRedirection })
        $Next = $script:Redirects[$Uri]
        Set-Variable -Name $StatusCodeVariable -Value $(if ($Next) { $script:RedirectStatus } else { 200 }) -Scope 1
        Set-Variable -Name $ResponseHeadersVariable -Value $(if ($Next) { @{ Location = $Next } } else { @{} }) -Scope 1
    }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Assert-CIPPWebhookDestination.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Send-CIPPAlert.ps1')
}

Describe 'Send-CIPPAlert -Type webhook' {
    BeforeEach {
        Mock Get-CIPPTable { @{ Context = 'ctx' } }
        Mock Write-LogMessage { }
        $script:Sent = [System.Collections.Generic.List[object]]::new()
        $script:Redirects = @{}
        $script:RedirectStatus = 307
        $script:Config = [pscustomobject]@{
            webhook            = 'https://8.8.8.8/hook'
            webhookAuthType    = 'customheaders'
            webhookAuthHeaders = '{"X-Api-Key":"k","x-ms-client-principal":"forged","X-MS-CLIENT-PRINCIPAL-NAME":"a","X-Forwarded-For":"1.2.3.4","Host":"localhost"}'
        }
        Mock Get-CIPPAzDataTableEntity {
            if ($Filter -like '*CippNotifications*') { return $script:Config }
            return $null
        }
    }

    It 'sends to a public https destination with automatic redirects off' {
        Send-CIPPAlert -Type 'webhook' -Title 'T' -JSONContent '{"a":1}' -TenantFilter 'contoso.onmicrosoft.com' | Out-Null
        $script:Sent.Count | Should -Be 1
        $script:Sent[0].Uri | Should -Be 'https://8.8.8.8/hook'
        $script:Sent[0].MaximumRedirection | Should -Be 0
    }

    It 'drops sign-in, forwarding and host headers but keeps the others' {
        Send-CIPPAlert -Type 'webhook' -Title 'T' -JSONContent '{"a":1}' -TenantFilter 'contoso.onmicrosoft.com' | Out-Null
        $Names = @($script:Sent[0].Headers.Keys)
        $Names | Should -Contain 'X-Api-Key'
        $Names | Where-Object { $_ -match '^(x-ms-client-principal|x-forwarded-|host$)' } | Should -BeNullOrEmpty
    }

    It 'drops a blocked name set as the single API key header' {
        $script:Config = [pscustomobject]@{ webhook = 'https://8.8.8.8/hook'; webhookAuthType = 'apikey'; webhookAuthHeaderName = 'X-MS-Client-Principal'; webhookAuthHeaderValue = 'forged' }
        Send-CIPPAlert -Type 'webhook' -Title 'T' -JSONContent '{"a":1}' -TenantFilter 'contoso.onmicrosoft.com' | Out-Null
        $script:Sent.Count | Should -Be 1
        @($script:Sent[0].Headers.Keys) | Should -Not -Contain 'X-MS-Client-Principal'
    }

    It 'does not send to <_>' -ForEach @(
        'https://127.0.0.1:8080/api/ExecCustomRole'
        'http://8.8.8.8/hook'
        'https://169.254.169.254/metadata'
    ) {
        $script:Config.webhook = $_
        $Result = Send-CIPPAlert -Type 'webhook' -Title 'T' -JSONContent '{"a":1}' -TenantFilter 'contoso.onmicrosoft.com'
        $script:Sent.Count | Should -Be 0
        $Result | Should -Match 'Webhook URL'
    }

    It 'follows a redirect to another public destination, including a relative one' {
        $script:Redirects = @{ 'https://8.8.8.8/hook' = '/moved'; 'https://8.8.8.8/moved' = 'https://1.1.1.1/final' }
        $Result = Send-CIPPAlert -Type 'webhook' -Title 'T' -JSONContent '{"a":1}' -TenantFilter 'contoso.onmicrosoft.com'
        $script:Sent.Uri | Should -Be @('https://8.8.8.8/hook', 'https://8.8.8.8/moved', 'https://1.1.1.1/final')
        $Result | Should -Match 'status code: 200'
    }

    It 'repeats the POST with its body on a <_> redirect' -ForEach @(307, 308) {
        $script:RedirectStatus = $_
        $script:Redirects = @{ 'https://8.8.8.8/hook' = 'https://1.1.1.1/final' }
        Send-CIPPAlert -Type 'webhook' -Title 'T' -JSONContent '{"a":1}' -TenantFilter 'contoso.onmicrosoft.com' | Should -Match 'status code: 200'
        $script:Sent[1].Method | Should -Be 'POST'
        $script:Sent[1].Body | Should -Not -BeNullOrEmpty
    }

    It 'continues as a GET without the body on a <_> redirect' -ForEach @(301, 302, 303) {
        $script:RedirectStatus = $_
        $script:Redirects = @{ 'https://8.8.8.8/hook' = 'https://1.1.1.1/result' }
        Send-CIPPAlert -Type 'webhook' -Title 'T' -JSONContent '{"a":1}' -TenantFilter 'contoso.onmicrosoft.com' | Should -Match 'status code: 200'
        $script:Sent.Count | Should -Be 2
        $script:Sent[1].Method | Should -Be 'GET'
        $script:Sent[1].Body | Should -BeNullOrEmpty
    }

    It 'does not follow a 303 redirect to a local address' {
        $script:RedirectStatus = 303
        $script:Redirects = @{ 'https://8.8.8.8/hook' = 'https://127.0.0.1:8080/api/me' }
        Send-CIPPAlert -Type 'webhook' -Title 'T' -JSONContent '{"a":1}' -TenantFilter 'contoso.onmicrosoft.com' | Should -Match 'Webhook URL'
        $script:Sent.Count | Should -Be 1
    }

    It 'does not follow a redirect to <_>' -ForEach @('https://127.0.0.1:8080/api/ExecCustomRole', 'http://1.1.1.1/plain', 'https://169.254.169.254/metadata') {
        $script:Redirects = @{ 'https://8.8.8.8/hook' = $_ }
        $Result = Send-CIPPAlert -Type 'webhook' -Title 'T' -JSONContent '{"a":1}' -TenantFilter 'contoso.onmicrosoft.com'
        $script:Sent.Count | Should -Be 1
        $Result | Should -Match 'Webhook URL'
    }

    It 'stops after three redirects' {
        $script:Redirects = @{ 'https://8.8.8.8/hook' = '/1'; 'https://8.8.8.8/1' = '/2'; 'https://8.8.8.8/2' = '/3'; 'https://8.8.8.8/3' = '/4'; 'https://8.8.8.8/4' = '/5' }
        $Result = Send-CIPPAlert -Type 'webhook' -Title 'T' -JSONContent '{"a":1}' -TenantFilter 'contoso.onmicrosoft.com'
        $script:Sent.Count | Should -Be 4
        $Result | Should -Match 'status code 307'
    }

    It 'checks an alternate webhook the same way' {
        $Result = Send-CIPPAlert -Type 'webhook' -Title 'T' -JSONContent '{"a":1}' -TenantFilter 'contoso.onmicrosoft.com' -altWebhook 'https://10.0.0.5/hook'
        $script:Sent.Count | Should -Be 0
        $Result | Should -Match 'Webhook URL'
    }
}
