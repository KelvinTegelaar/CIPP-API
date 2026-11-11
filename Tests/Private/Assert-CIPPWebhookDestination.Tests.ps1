# Pester tests for Assert-CIPPWebhookDestination. IP literals and localhost only, so no DNS lookups leave the machine.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Assert-CIPPWebhookDestination.ps1')
}

Describe 'Assert-CIPPWebhookDestination' {
    It 'allows <_>' -ForEach @(
        'https://8.8.8.8/hook'
        'https://1.1.1.1:8443/hook?x=1'
        'https://[2606:4700:4700::1111]/hook'
        'https://172.32.0.1/hook'
        'https://100.128.0.1/hook'
    ) {
        { Assert-CIPPWebhookDestination -Uri $_ } | Should -Not -Throw
    }

    It 'refuses <_>' -ForEach @(
        'http://8.8.8.8/hook'
        'https://user:pass@8.8.8.8/hook'
        '8.8.8.8/hook'
        'ftp://8.8.8.8/hook'
        'https://127.0.0.1:8080/api/ExecCustomRole'
        'https://127.9.9.9/'
        'https://localhost:8080/'
        'https://0.0.0.0/'
        'https://10.1.2.3/'
        'https://172.16.0.1/'
        'https://172.31.255.254/'
        'https://192.168.1.10/'
        'https://169.254.169.254/metadata/identity'
        'https://100.64.0.1/'
        'https://[::1]:8080/'
        'https://[::]/'
        'https://[fe80::1]/'
        'https://[fd00::1]/'
        'https://[::ffff:127.0.0.1]/'
        'https://[::ffff:10.0.0.1]/'
        'https://2130706433/'
        'https://does-not-resolve.invalid/'
    ) {
        { Assert-CIPPWebhookDestination -Uri $_ } | Should -Throw '*Webhook URL*'
    }
}
