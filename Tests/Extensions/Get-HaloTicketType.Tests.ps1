BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPTable { param($TableName) @{} }
    function Get-CIPPAzDataTableEntity {
        [pscustomobject]@{ config = (@{ HaloPSA = @{ ResourceURL = 'https://halo.example.com/api'; ClientID = 'x' } } | ConvertTo-Json -Compress) }
    }
    function Get-HaloToken { param($configuration) @{ access_token = 'token' } }
    function Get-CippUserAgent { 'CIPP/test' }
    function Get-NormalizedError { param($Message) $Message }

    . (Join-Path $RepoRoot 'Modules/CippExtensions/Public/Halo/Get-HaloTicketType.ps1')
}

Describe 'Get-HaloTicketType' {
    It 'emits one row per ticket type when Halo answers with a JSON array' {
        # Invoke-RestMethod hands a top-level JSON array back as a single Object[], matching Halo's /TicketType response.
        Mock Invoke-RestMethod { , @([pscustomobject]@{ id = 21; name = 'Alert' }, [pscustomobject]@{ id = 1; name = 'Incident' }) }

        $Result = @(Get-HaloTicketType)

        $Result.Count | Should -Be 2
        $Result[0].id | Should -Be 21
        $Result[1].name | Should -Be 'Incident'
    }
}
