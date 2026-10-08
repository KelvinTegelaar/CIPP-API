BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StandardPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-CIPPStandardAddDMARCToMOERA.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $StandardPath) { throw 'Could not locate Invoke-CIPPStandardAddDMARCToMOERA.ps1 under Modules/' }

    function New-GraphGetRequest { [CmdletBinding()] param($TenantID, $Uri) }
    function Read-DmarcPolicy { [CmdletBinding()] param($Domain) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $FieldValue, $CurrentValue, $ExpectedValue, $TenantFilter) }
    function Write-LogMessage { [CmdletBinding()] param($message, $tenant, $API, $headers, $sev, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Get-CippException { [CmdletBinding()] param($Exception) [PSCustomObject]@{ NormalizedError = [string]$Exception } }

    . $StandardPath
}

Describe 'Invoke-CIPPStandardAddDMARCToMOERA alert' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock Write-Warning {}
        Mock Write-StandardsAlert {}
        Mock New-GraphGetRequest { @(@{ id = 'a.onmicrosoft.com' }, @{ id = 'b.onmicrosoft.com' }, @{ id = 'a.mail.onmicrosoft.com' }) }
        Mock Read-DmarcPolicy {
            switch ($Domain) {
                'a.onmicrosoft.com' { [PSCustomObject]@{ Record = 'v=DMARC1; p=reject;' } }
                'b.onmicrosoft.com' { [PSCustomObject]@{ Record = $null } }
            }
        }
    }

    It 'lists only the domains whose record does not match' {
        Invoke-CIPPStandardAddDMARCToMOERA -Tenant 'contoso.onmicrosoft.com' -Settings ([PSCustomObject]@{ alert = $true })
        Should -Invoke Write-StandardsAlert -Times 1 -ParameterFilter {
            $object.MissingDMARC -eq 'b.onmicrosoft.com' -and $message -like '*1 of 2*'
        }
    }
}
