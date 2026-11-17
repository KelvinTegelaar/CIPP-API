# Pester tests for Get-CIPPOneDriveCopyUser: user + OneDrive resolution and its refusals

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPOneDriveCopyUser.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate $FunctionPath" }

    function New-GraphGetRequest { param($uri, $tenantid, $asapp) }

    . $FunctionPath

    $script:Licensed = @([pscustomobject]@{ service = 'SharePoint'; capabilityStatus = 'Enabled' })
    $script:Unlicensed = @([pscustomobject]@{ service = 'exchange'; capabilityStatus = 'Enabled' }, [pscustomobject]@{ service = 'SharePoint'; capabilityStatus = 'Deleted' })
}

Describe 'Get-CIPPOneDriveCopyUser' {
    BeforeEach {
        $script:Plans = $script:Licensed
        $script:UserType = 'Member'
        $script:Upn = 'bob@contoso.com'
        $script:ExternalState = $null
        Mock New-GraphGetRequest {
            switch -Wildcard ($uri) {
                '*/users/*/drive?*' { [pscustomobject]@{ id = 'drive-bob'; webUrl = 'https://contoso-my.sharepoint.com/personal/bob_contoso_com/Documents'; driveType = 'business'; quota = [pscustomobject]@{ remaining = 1000; total = 5000 } }; break }
                '*/users/*' { [pscustomobject]@{ id = 'u-bob'; userPrincipalName = $script:Upn; displayName = 'Bob'; accountEnabled = $false; userType = $script:UserType; externalUserState = $script:ExternalState; assignedPlans = $script:Plans }; break }
                '*/root?*' { [pscustomobject]@{ id = 'root-bob'; sharepointIds = [pscustomobject]@{ siteUrl = 'https://contoso-my.sharepoint.com/personal/bob_contoso_com' } } }
            }
        }
    }

    It 'resolves the user, drive, site and quota' {
        $Result = Get-CIPPOneDriveCopyUser -TenantFilter 'contoso.com' -UserId 'bob@contoso.com'
        $Result.UserId | Should -Be 'u-bob'
        $Result.DriveId | Should -Be 'drive-bob'
        $Result.DriveHost | Should -Be 'contoso-my.sharepoint.com'
        $Result.SiteUrl | Should -Be 'https://contoso-my.sharepoint.com/personal/bob_contoso_com'
        $Result.QuotaRemaining | Should -Be 1000
        $Result.AccountEnabled | Should -BeFalse
        $Result.UserType | Should -Be 'Member'
        Should -Invoke New-GraphGetRequest -ParameterFilter { $uri -like '*/users/*$select=*accountEnabled*userType*externalUserState*' }
        Should -Invoke New-GraphGetRequest -ParameterFilter { $uri -like '*/users/bob%40contoso.com?*' -and $tenantid -eq 'contoso.com' }
    }

    It 'falls back to the library parent when the root has no sharepointIds' {
        Mock New-GraphGetRequest { [pscustomobject]@{ id = 'root-bob' } } -ParameterFilter { $uri -like '*/root?*' }
        (Get-CIPPOneDriveCopyUser -TenantFilter 'contoso.com' -UserId 'bob@contoso.com').SiteUrl | Should -Be 'https://contoso-my.sharepoint.com/personal/bob_contoso_com'
    }

    It 'refuses <Case> with ArgumentException' -ForEach @(
        @{ Case = 'a malformed id'; Id = 'bob/../x'; Kind = 'Recipient'; Setup = {}; Message = "*is not a user principal name or object id*" }
        @{ Case = 'an unknown user'; Id = 'nobody@contoso.com'; Kind = 'Recipient'; Setup = { Mock New-GraphGetRequest { throw 'Request_ResourceNotFound: Resource does not exist' } -ParameterFilter { $uri -like '*/users/*' -and $uri -notlike '*/drive?*' } }; Message = '*was not found in tenant contoso.com*' }
        @{ Case = 'a recipient without a OneDrive licence'; Id = 'bob@contoso.com'; Kind = 'Recipient'; Setup = { $script:Plans = $script:Unlicensed }; Message = '*has no licence that includes OneDrive*' }
        @{ Case = 'a user without a OneDrive'; Id = 'bob@contoso.com'; Kind = 'Leaver'; Setup = { Mock New-GraphGetRequest { throw 'itemNotFound: mysite not found' } -ParameterFilter { $uri -like '*/drive?*' } }; Message = 'Leaver bob@contoso.com has no OneDrive*' }
    ) {
        . $Setup
        { Get-CIPPOneDriveCopyUser -TenantFilter 'contoso.com' -UserId $Id -Kind $Kind } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage $Message
    }

    It 'accepts and escapes a <Case> UPN' -ForEach @(
        @{ Case = 'guest (#EXT#)'; Id = 'jo_fabrikam.com#EXT#@contoso.onmicrosoft.com'; Escaped = 'jo_fabrikam.com%23EXT%23%40contoso.onmicrosoft.com' }
        @{ Case = 'apostrophe and plus'; Id = "o'brien+it@contoso.com"; Escaped = 'o%27brien%2Bit%40contoso.com' }
        @{ Case = 'unicode'; Id = 'zoë@contoso.com'; Escaped = 'zo%C3%AB%40contoso.com' }
    ) {
        $null = Get-CIPPOneDriveCopyUser -TenantFilter 'contoso.com' -UserId $Id
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like "https://graph.microsoft.com/v1.0/users/$Escaped`?*" }
    }

    It 'accepts an object id' {
        $null = Get-CIPPOneDriveCopyUser -TenantFilter 'contoso.com' -UserId '0f9f1b2c-1111-2222-3333-444455556666'
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like 'https://graph.microsoft.com/v1.0/users/0f9f1b2c-1111-2222-3333-444455556666?*' }
    }

    It 'still refuses <Case>' -ForEach @(
        @{ Case = 'a # in the domain'; Id = 'bob@contoso.com#x' }
        @{ Case = 'a query string'; Id = 'bob@contoso.com?$select=x' }
        @{ Case = 'a second @'; Id = 'a@b@contoso.com' }
    ) {
        { Get-CIPPOneDriveCopyUser -TenantFilter 'contoso.com' -UserId $Id } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*is not a user principal name or object id*'
        Should -Invoke New-GraphGetRequest -Times 0 -Exactly
    }

    It 'does not require a licence for the leaver' {
        $script:Plans = $script:Unlicensed
        (Get-CIPPOneDriveCopyUser -TenantFilter 'contoso.com' -UserId 'bob@contoso.com' -Kind Leaver).HasOneDrivePlan | Should -BeFalse
    }

    It 'lets upstream failures through untyped' {
        Mock New-GraphGetRequest { throw 'Graph 503 Service Unavailable' } -ParameterFilter { $uri -like '*/drive?*' }
        $Thrown = { Get-CIPPOneDriveCopyUser -TenantFilter 'contoso.com' -UserId 'bob@contoso.com' } | Should -Throw -PassThru
        $Thrown.Exception | Should -Not -BeOfType ([System.ArgumentException])
    }
    It 'refuses a guest recipient' {
        $script:UserType = 'Guest'
        { Get-CIPPOneDriveCopyUser -TenantFilter 'contoso.com' -UserId 'bob@contoso.com' -Kind Recipient } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage 'Recipient bob@contoso.com is a guest*'
        Should -Invoke New-GraphGetRequest -Times 0 -Exactly -ParameterFilter { $uri -like '*/drive?*' }
    }

    It 'refuses an outside identity as recipient even when userType is not Guest (<Case>)' -ForEach @(
        @{ Case = 'B2B user converted to Member'; UserType = 'Member'; Upn = 'jo_fabrikam.com#EXT#@contoso.onmicrosoft.com'; State = 'Accepted' }
        @{ Case = 'userType missing, #EXT# UPN'; UserType = $null; Upn = 'jo_fabrikam.com#EXT#@contoso.onmicrosoft.com'; State = $null }
        @{ Case = 'Member with a pending invitation'; UserType = 'Member'; Upn = 'jo@contoso.com'; State = 'PendingAcceptance' }
    ) {
        $script:UserType = $UserType; $script:Upn = $Upn; $script:ExternalState = $State
        { Get-CIPPOneDriveCopyUser -TenantFilter 'contoso.com' -UserId 'bob@contoso.com' -Kind Recipient } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage "Recipient $Upn is an account from another organisation (an invited user, or one synced in from another tenant). Only members of this tenant can receive the copy."
        Should -Invoke New-GraphGetRequest -Times 0 -Exactly -ParameterFilter { $uri -like '*/drive?*' }
    }

    It 'accepts an internal member whose userType is not set' {
        $script:UserType = $null
        (Get-CIPPOneDriveCopyUser -TenantFilter 'contoso.com' -UserId 'bob@contoso.com' -Kind Recipient).UserId | Should -Be 'u-bob'
    }

    It 'allows a guest leaver' {
        $script:UserType = 'Guest'
        (Get-CIPPOneDriveCopyUser -TenantFilter 'contoso.com' -UserId 'bob@contoso.com' -Kind Leaver).UserType | Should -Be 'Guest'
    }
}
