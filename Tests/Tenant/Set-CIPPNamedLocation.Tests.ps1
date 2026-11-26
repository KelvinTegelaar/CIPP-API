# Graph refuses to delete a trusted IP location (error 1177), so delete marks it untrusted first.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-GraphGetRequest { param($uri, $Tenantid) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $body, $type) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }

    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/Set-CIPPNamedLocation.ps1')
}

Describe 'Set-CIPPNamedLocation delete' {
    BeforeEach {
        $script:Calls = [System.Collections.Generic.List[string]]::new()
        Mock -CommandName New-GraphPOSTRequest -MockWith { $script:Calls.Add("$type $body") }
    }

    It 'marks a trusted IP location untrusted before deleting it' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{ '@odata.type' = '#microsoft.graph.ipNamedLocation'; displayName = 'Office'; isTrusted = $true }
        }
        $Result = Set-CIPPNamedLocation -NamedLocationId 'abc' -TenantFilter 'ok.example' -Change 'delete'
        $Result | Should -Be 'Deleted named location: Office'
        $script:Calls.Count | Should -Be 2
        $script:Calls[0] | Should -Be 'PATCH {"@odata.type":"#microsoft.graph.ipNamedLocation","isTrusted":false}'
        $script:Calls[1] | Should -Match '^DELETE'
    }

    It 'deletes an untrusted IP location with a single call' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{ '@odata.type' = '#microsoft.graph.ipNamedLocation'; displayName = 'Office'; isTrusted = $false }
        }
        $null = Set-CIPPNamedLocation -NamedLocationId 'abc' -TenantFilter 'ok.example' -Change 'delete'
        $script:Calls.Count | Should -Be 1
        $script:Calls[0] | Should -Match '^DELETE'
    }

    It 'deletes a country location with a single call' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{ '@odata.type' = '#microsoft.graph.countryNamedLocation'; displayName = 'Blocked' }
        }
        $null = Set-CIPPNamedLocation -NamedLocationId 'abc' -TenantFilter 'ok.example' -Change 'delete'
        $script:Calls.Count | Should -Be 1
        $script:Calls[0] | Should -Match '^DELETE'
    }
}
