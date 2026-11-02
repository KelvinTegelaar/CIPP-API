BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, $NoAuthCheck) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Webhooks/Get-CIPPPartnerUserLookup.ps1')
}

Describe 'Get-CIPPPartnerUserLookup' {
    BeforeEach {
        # the per-worker memo lives in the dot-sourcing scope here; start each test cold
        $script:PartnerUserMemo = $null
        Mock Get-CIPPAzDataTableEntity { $null }
        Mock Add-CIPPAzDataTableEntity {}
        Mock New-GraphGetRequest { @() }
    }

    It 'serves the day-old table cache without touching Graph' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ Format = 'hashtable'; Data = (@{ 'id-1' = @{ userPrincipalName = 'tech@msp.example' } } | ConvertTo-Json -Compress) } }
        $Lookup = Get-CIPPPartnerUserLookup
        $Lookup['id-1'].userPrincipalName | Should -Be 'tech@msp.example'
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Filter -like "PartitionKey eq '_partner' and RowKey eq 'users'*" }
        Should -Invoke New-GraphGetRequest -Times 0
    }

    It 'reads the partner tenant from Graph on a cache miss, keys by id, and writes the cache row back' {
        Mock New-GraphGetRequest { @([pscustomobject]@{ id = 'id-2'; userPrincipalName = 'two@msp.example' }, [pscustomobject]@{ id = ''; userPrincipalName = 'ghost' }) }
        $Lookup = Get-CIPPPartnerUserLookup
        @($Lookup.Keys) | Should -Be @('id-2')
        Should -Invoke New-GraphGetRequest -Times 1 -ParameterFilter { $uri -like 'https://graph.microsoft.com/beta/users?*' -and $AsApp -eq $true -and $NoAuthCheck -eq $true }
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Entity.PartitionKey -eq '_partner' -and $Entity.RowKey -eq 'users' -and $Entity.Format -eq 'hashtable' -and $Entity.Data -like '*two@msp.example*' }
    }

    It 'memoises the answer for the worker so a second call inside the window reads nothing' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ Format = 'hashtable'; Data = (@{ 'id-1' = @{ userPrincipalName = 'tech@msp.example' } } | ConvertTo-Json -Compress) } }
        $null = Get-CIPPPartnerUserLookup
        $Again = Get-CIPPPartnerUserLookup
        $Again['id-1'].userPrincipalName | Should -Be 'tech@msp.example'
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly
    }
}
