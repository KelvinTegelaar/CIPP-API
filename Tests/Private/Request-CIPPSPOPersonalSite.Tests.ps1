# Pester tests for Request-CIPPSPOPersonalSite - OneDrive pre-provisioning must run DELEGATED. SharePoint
# refuses every app-only token on both CSOM routes (pnp/powershell#4329, CyberDrain/CIPP#592), so these
# pin: no app-only/certificate auth, User Profile Service route first, RequestPersonalSites as fallback,
# CSOM ErrorInfo surfaced instead of a false success.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Request-CIPPSPOPersonalSite.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Request-CIPPSPOPersonalSite.ps1 under Modules/' }

    function Get-SharePointAdminLink { param($Public, $TenantFilter) }
    function New-GraphPostRequest { param($scope, $tenantid, $Uri, $Type, $Body, $ContentType, $AsApp, [switch]$UseCertificate) }
    function Write-LogMessage { param($headers, $API, $message, $Sev, $tenant, $LogData) }
    function Get-CippException { param($Exception) [PSCustomObject]@{ NormalizedError = $Exception.Exception.Message } }

    . $FunctionPath

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:AdminUrl = 'https://contoso-admin.sharepoint.com'
    $script:Ok = @([PSCustomObject]@{ SchemaVersion = '15.0.0.0'; ErrorInfo = $null; IsComplete = $true })
    $script:Refused = @([PSCustomObject]@{ ErrorInfo = [PSCustomObject]@{ ErrorMessage = 'Attempted to perform an unauthorized operation.'; ErrorTypeName = 'System.UnauthorizedAccessException' }; IsComplete = $false })
}

Describe 'Request-CIPPSPOPersonalSite' {
    BeforeEach {
        Mock Get-SharePointAdminLink { [PSCustomObject]@{ AdminUrl = $script:AdminUrl; TenantName = 'contoso'; SharePointDomain = 'sharepoint.com' } }
        Mock Write-LogMessage { }
        Mock New-GraphPostRequest { $script:Ok }
    }

    It 'enqueues through the User Profile Service DELEGATED on the admin site - never app-only or certificate' {
        $Result = Request-CIPPSPOPersonalSite -TenantFilter $script:Tenant -UserEmails 'user1@contoso.com'
        $Result | Should -Be 'Successfully requested personal site for user1@contoso.com'
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter {
            -not $AsApp -and -not $UseCertificate -and
            $scope -eq "$($script:AdminUrl)/.default" -and
            $Uri -eq "$($script:AdminUrl)/_vti_bin/client.svc/ProcessQuery" -and
            $Body -match 'StaticMethod[^>]+Name="GetProfileLoader"[^>]+TypeId="\{9c42543a-91b3-4902-b2fe-14ccdefb6e2b\}"' -and
            $Body -match 'Name="CreatePersonalSiteEnqueueBulk"' -and
            $Body -notmatch 'RequestPersonalSites' -and
            $Body -match "<Object Type='String'>user1@contoso.com</Object>"
        }
    }

    It 'falls back to Tenant.RequestPersonalSites when the User Profile route is refused' {
        Mock New-GraphPostRequest { if ($Body -match 'CreatePersonalSiteEnqueueBulk') { $script:Refused } else { $script:Ok } }
        $Result = Request-CIPPSPOPersonalSite -TenantFilter $script:Tenant -UserEmails 'user1@contoso.com'
        $Result | Should -Be 'Successfully requested personal site for user1@contoso.com'
        Should -Invoke New-GraphPostRequest -Times 2 -Exactly
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter {
            -not $AsApp -and -not $UseCertificate -and
            $Body -match 'Constructor[^>]+TypeId="\{268004ae-ef6b-4e9b-8425-127220d84719\}"' -and
            $Body -match 'Name="RequestPersonalSites"' -and
            $Body -match "<Object Type='String'>user1@contoso.com</Object>"
        }
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Warning' -and $message -like 'ProfileLoader.CreatePersonalSiteEnqueueBulk refused*' }
    }

    It 'escapes user values so a UPN cannot break out of the CSOM XML' {
        Request-CIPPSPOPersonalSite -TenantFilter $script:Tenant -UserEmails "o'brien<x>@contoso.com" | Out-Null
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter {
            $Body -match "o&apos;brien&lt;x&gt;@contoso.com" -and $Body -notmatch '<x>'
        }
    }

    It 'splits more than 200 users across calls' {
        $Users = 1..201 | ForEach-Object { "user$_@contoso.com" }
        Request-CIPPSPOPersonalSite -TenantFilter $script:Tenant -UserEmails $Users | Out-Null
        Should -Invoke New-GraphPostRequest -Times 2 -Exactly
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $Body -match 'user201@contoso.com' -and $Body -notmatch 'user1@contoso.com<' }
    }

    It 'fails with both refusals and the SharePoint Administrator hint when every route is refused' {
        Mock New-GraphPostRequest { $script:Refused }
        { Request-CIPPSPOPersonalSite -TenantFilter $script:Tenant -UserEmails 'user1@contoso.com' } |
            Should -Throw -ExpectedMessage "*ProfileLoader.CreatePersonalSiteEnqueueBulk - Attempted to perform an unauthorized operation.*Tenant.RequestPersonalSites - Attempted*SharePoint Administrator role in $($script:Tenant)*"
        Should -Invoke New-GraphPostRequest -Times 2 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Error' }
    }

    It 'fails when SharePoint answers without IsComplete on every route' {
        Mock New-GraphPostRequest { @([PSCustomObject]@{ ErrorInfo = $null; IsComplete = $false }) }
        { Request-CIPPSPOPersonalSite -TenantFilter $script:Tenant -UserEmails 'user1@contoso.com' } |
            Should -Throw -ExpectedMessage '*did not confirm the personal site request*'
    }
}
