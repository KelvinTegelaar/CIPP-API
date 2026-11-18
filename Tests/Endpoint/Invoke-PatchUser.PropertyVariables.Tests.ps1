# A bulk edit can set a value built from each user's own properties, e.g. displayName = '%givenName% %surname% (Contoso)'.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Assert-CippPrivilegedUserAccess { param($TenantFilter, $UserId, [switch]$PassThru) }
    function New-GraphBulkRequest { param($tenantid, $Requests) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev) }
    function Set-CIPPManager { param($Users, $Manager, $TenantFilter, $Headers, $APIName) }
    function Set-CIPPSponsor { param($Users, $Sponsor, $TenantFilter, $Headers, $APIName) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text) }

    . (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/Users/Invoke-PatchUser.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Resolve-CIPPUserPropertyText.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippBulkStatusCode.ps1')

    function New-PatchRequest([object[]]$Users) {
        [pscustomobject]@{ Body = $Users; Headers = @{}; Params = @{ CIPPEndpoint = 'PatchUser' }; Query = @{} }
    }

    $Directory = @{
        'u1' = [pscustomobject]@{ givenName = 'Jane'; surname = 'Doe' }
        'u2' = [pscustomobject]@{ givenName = 'Sam'; surname = '' }
    }
}

Describe 'Invoke-PatchUser property variables' {
    BeforeEach {
        $script:Patches = [System.Collections.Generic.List[object]]::new()
        Mock Write-LogMessage { }
        Mock Assert-CippPrivilegedUserAccess { @() }
        # Stands in for tenant and custom variables: only %tenantname% and %region% are known.
        Mock Get-CIPPTextReplacement { $Text -replace '%tenantname%', 'Contoso' -replace '%region%', 'EU' }
        Mock New-GraphBulkRequest {
            foreach ($R in $Requests) {
                if ($R.method -eq 'GET') {
                    $Id = ($R.url -split '[/?]')[1]
                    if ($Directory[$Id]) { [pscustomobject]@{ id = $R.id; status = 200; body = $Directory[$Id] } }
                    else { [pscustomobject]@{ id = $R.id; status = 404; body = @{ error = @{ message = 'Resource not found' } } } }
                } else {
                    $script:Patches.Add($R)
                    [pscustomobject]@{ id = $R.id; status = 204 }
                }
            }
        }
    }

    It 'fills each user''s value from their own properties, reading only the referenced ones' {
        $Response = Invoke-PatchUser -Request (New-PatchRequest @(
                [pscustomobject]@{ id = 'u1'; tenantFilter = 'a.com'; displayName = '%FirstName% %surname% (Contoso)'; jobTitle = 'Bot' }
            ))
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter { $Requests[0].method -eq 'GET' -and $Requests[0].url -match '\$select=givenName,surname$' }
        $script:Patches.Count | Should -Be 1
        $script:Patches[0].body.displayName | Should -Be 'Jane Doe (Contoso)'
        $script:Patches[0].body.jobTitle | Should -Be 'Bot'
    }

    It 'replaces tenant and custom variables first and reads only the remaining tokens from the user' {
        $null = Invoke-PatchUser -Request (New-PatchRequest @(
                [pscustomobject]@{ id = 'u1'; tenantFilter = 'a.com'; displayName = '%givenName% (%tenantname% %region%)' }
            ))
        Should -Invoke Get-CIPPTextReplacement -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq 'a.com' }
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter { $Requests[0].method -eq 'GET' -and $Requests[0].url -match '\$select=givenName$' }
        $script:Patches[0].body.displayName | Should -Be 'Jane (Contoso EU)'
    }

    It 'needs no user read when every token is a tenant or custom variable' {
        $null = Invoke-PatchUser -Request (New-PatchRequest @(
                [pscustomobject]@{ id = 'u1'; tenantFilter = 'a.com'; companyName = '%tenantname%' }
            ))
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly
        $script:Patches[0].body.companyName | Should -Be 'Contoso'
    }

    It 'skips and reports a user whose property is empty, and patches the rest' {
        $Response = Invoke-PatchUser -Request (New-PatchRequest @(
                [pscustomobject]@{ id = 'u1'; tenantFilter = 'a.com'; displayName = '%givenName% %surname%' }
                [pscustomobject]@{ id = 'u2'; tenantFilter = 'a.com'; displayName = '%givenName% %surname%' }
            ))
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]207)
        @($Response.Body.Results)[0] | Should -Be 'Failed to patch user u2 in tenant a.com: %surname% has no value for this user'
        @($script:Patches.url) | Should -Be @('users/u1')
    }

    It 'skips a user whose properties cannot be read' {
        $Response = Invoke-PatchUser -Request (New-PatchRequest @(
                [pscustomobject]@{ id = 'gone'; tenantFilter = 'a.com'; displayName = '%givenName%' }
            ))
        @($Response.Body.Results)[0] | Should -Be 'Failed to patch user gone in tenant a.com: Resource not found'
        $script:Patches.Count | Should -Be 0
    }

    It 'makes no extra read when no value has a token' {
        $null = Invoke-PatchUser -Request (New-PatchRequest @(
                [pscustomobject]@{ id = 'u1'; tenantFilter = 'a.com'; displayName = 'Service Bot' }
            ))
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly
        $script:Patches[0].body.displayName | Should -Be 'Service Bot'
    }
}
