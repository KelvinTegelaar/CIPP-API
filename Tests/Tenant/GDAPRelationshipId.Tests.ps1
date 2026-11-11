# Pester tests for GDAP relationship id validation on the endpoints that place it in a Graph URL.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
        [object]$ContentType
    }

    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$($Exception.Exception.Message)" } }
    function Get-NormalizedError { param($Message) $Message }
    function Get-CIPPPartnerTenantList { }
    function New-GraphGetRequest { param($Uri, $tenantid, $NoAuthCheck, $NoPagination, [switch]$ComplexFilter, $AsApp) }
    function New-GraphPostRequest { param($Uri, $tenantid, $type, $body, $NoAuthCheck, $AddedHeaders) }
    function New-GraphBulkRequest { param($Requests, $tenantid, $NoAuthCheck, $AsApp) }
    function Set-CIPPGDAPAutoExtend { param($RelationShipid, $PartnerTenantId) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Test-IsGuid.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Test-CIPPGDAPRelationshipId.ps1')
    foreach ($Name in 'Invoke-ListGDAPRelationships', 'Invoke-ListGDAPAccessAssignments', 'Invoke-ExecGDAPAccessAssignment', 'Invoke-ExecDeleteGDAPRelationship', 'Invoke-ExecGDAPRemoveGArole', 'Invoke-ExecAutoExtendGDAP') {
        $Path = (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules/CIPPHTTP') -Recurse -Filter "$Name.ps1").FullName
        . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $Path -Raw)))
    }

    $script:GoodId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa-bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
}

Describe 'Test-CIPPGDAPRelationshipId' {
    It 'accepts two GUIDs joined by a hyphen' {
        Test-CIPPGDAPRelationshipId -Id $script:GoodId | Should -BeTrue
    }

    It 'refuses <_>' -ForEach @(
        '../../users'
        '../../organization'
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa-bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/requests'
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa-bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb?x'
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa-bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb#x'
        ''
    ) {
        Test-CIPPGDAPRelationshipId -Id $_ | Should -BeFalse
    }
}

Describe 'GDAP endpoints refuse a malformed relationship id' {
    BeforeEach {
        $env:TenantID = 'partner-tenant-id'
        Mock Get-CIPPPartnerTenantList { [pscustomobject]@{ partnerTenantId = 'partner-tenant-id'; RowKey = 'partner-tenant-id' } }
        Mock New-GraphGetRequest { }
        Mock New-GraphPostRequest { }
        Mock New-GraphBulkRequest { }
        Mock Set-CIPPGDAPAutoExtend { }
        Mock Write-LogMessage { }
    }

    It '<Endpoint> returns 400 and calls nothing' -ForEach @(
        @{ Endpoint = 'Invoke-ListGDAPRelationships'; Query = @{ id = '../../users?$top=1' }; Body = @{} }
        @{ Endpoint = 'Invoke-ListGDAPAccessAssignments'; Query = @{ Id = '../../users' }; Body = @{} }
        @{ Endpoint = 'Invoke-ExecGDAPAccessAssignment'; Query = @{}; Body = @{ Action = 'ResetMappings'; Id = '../../users'; RoleTemplateId = 'T' } }
        @{ Endpoint = 'Invoke-ExecDeleteGDAPRelationship'; Query = @{}; Body = @{ GDAPId = '../../users/x' } }
        @{ Endpoint = 'Invoke-ExecGDAPRemoveGArole'; Query = @{}; Body = @{ GDAPId = '../../users/x' } }
        @{ Endpoint = 'Invoke-ExecAutoExtendGDAP'; Query = @{}; Body = @{ ID = '../../users/x' } }
    ) {
        $Request = [pscustomobject]@{ Params = @{ CIPPEndpoint = $Endpoint }; Headers = @{}; Query = [pscustomobject]$Query; Body = [pscustomobject]$Body }
        $Response = & $Endpoint -Request $Request -TriggerMetadata $null
        $Response.StatusCode | Should -Be 400
        Should -Invoke New-GraphGetRequest -Times 0 -Exactly
        Should -Invoke New-GraphPostRequest -Times 0 -Exactly
        Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
        Should -Invoke Set-CIPPGDAPAutoExtend -Times 0 -Exactly
    }

    It 'ListGDAPRelationships looks up a well-formed id' {
        Mock New-GraphGetRequest { [pscustomobject]@{ id = $script:GoodId } }
        $Request = [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ListGDAPRelationships' }; Headers = @{}; Query = [pscustomobject]@{ id = $script:GoodId }; Body = [pscustomobject]@{} }
        (Invoke-ListGDAPRelationships -Request $Request -TriggerMetadata $null).StatusCode | Should -Be 200
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships/$($script:GoodId)" }
    }

    It 'ExecAutoExtendGDAP passes a well-formed id on' {
        $Request = [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecAutoExtendGDAP' }; Headers = @{}; Query = [pscustomobject]@{}; Body = [pscustomobject]@{ ID = $script:GoodId } }
        (Invoke-ExecAutoExtendGDAP -Request $Request -TriggerMetadata $null).StatusCode | Should -Be 200
        Should -Invoke Set-CIPPGDAPAutoExtend -Times 1 -Exactly
    }
}
