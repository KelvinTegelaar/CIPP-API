BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPGSAProfileLinks.ps1')
    function New-GraphPOSTRequest { param($uri, $tenantid, $AsApp, $type, $body) }
    function Get-NormalizedError { param($Message) $Message }
    $script:Writes = [System.Collections.Generic.List[object]]::new()

    function Get-Link([string]$Id, [string]$PolicyId, [int]$Priority, [string]$Logging = 'enabled') {
        [pscustomobject]@{ id = $Id; priority = $Priority; state = 'enabled'; loggingState = $Logging; policy = [pscustomobject]@{ id = $PolicyId; name = "Policy $PolicyId" } }
    }
    function Get-Wanted([string]$PolicyId, [int]$Priority, [string]$Logging = 'enabled') {
        [pscustomobject]@{ policyId = $PolicyId; policyName = "Policy $PolicyId"; priority = $Priority; state = 'enabled'; loggingState = $Logging }
    }
    function Invoke-Links($Links, $Current) {
        @(Set-CIPPGSAProfileLinks -TenantFilter 'contoso.com' -ProfileId 'prof' -ProfileName 'Staff' -Links $Links -Current $Current)
    }
}

Describe 'Set-CIPPGSAProfileLinks' {
    BeforeEach {
        $script:Writes.Clear()
        Mock New-GraphPOSTRequest { $script:Writes.Add([pscustomobject]@{ type = $type; uri = ($uri -replace '^.*/filteringProfiles/prof/policies', ''); body = $body }) }
    }

    It 'swaps two link priorities through a free temporary priority, because priorities are unique' {
        $Results = Invoke-Links -Links @((Get-Wanted 'a' 200), (Get-Wanted 'b' 100)) -Current @((Get-Link 'la' 'a' 100), (Get-Link 'lb' 'b' 200))
        @($script:Writes | ForEach-Object { "$($_.type) $($_.uri) $((($_.body | ConvertFrom-Json).priority))" }) | Should -Be @(
            'PATCH /la 65000'
            'PATCH /lb 64999'
            'PATCH /la 200'
            'PATCH /lb 100'
        )
        @($Results.state | Sort-Object -Unique) | Should -Be @('success')
    }

    It 'patches directly when the target priorities are free' {
        $null = Invoke-Links -Links @((Get-Wanted 'a' 300)) -Current @((Get-Link 'la' 'a' 100))
        @($script:Writes | ForEach-Object { "$($_.type) $($_.uri)" }) | Should -Be @('PATCH /la')
    }

    It 'unlinks unwanted links first, recreates a link whose logging changes, and creates new links last' {
        $Results = Invoke-Links -Links @((Get-Wanted 'a' 100 'disabled'), (Get-Wanted 'c' 300)) -Current @((Get-Link 'la' 'a' 100), (Get-Link 'lx' 'x' 200))
        @($script:Writes | ForEach-Object { "$($_.type) $($_.uri)" }) | Should -Be @('DELETE /la', 'DELETE /lx', 'POST ', 'POST ')
        ($script:Writes[2].body | ConvertFrom-Json).loggingState | Should -Be 'disabled'
        @($Results.resultText) | Should -Be @("Unlinked 'Staff -> Policy x'", "Recreated link 'Staff -> Policy a' to disable logging", "Linked 'Policy c' to security profile 'Staff'")
    }

    It 'does not try to update an unwanted link whose delete failed' {
        Mock New-GraphPOSTRequest { throw 'Graph said no' } -ParameterFilter { $type -eq 'DELETE' }
        $Results = Invoke-Links -Links @() -Current @((Get-Link 'lx' 'x' 200))
        @($Results.resultText) | Should -Be @("Failed to unlink 'Staff -> Policy x': Graph said no")
        Should -Invoke New-GraphPOSTRequest -Times 0 -ParameterFilter { $type -ne 'DELETE' }
    }

    It 'treats missing lists as empty' {
        @(Invoke-Links -Links $null -Current $null).Count | Should -Be 0
        $script:Writes.Count | Should -Be 0
    }
}
