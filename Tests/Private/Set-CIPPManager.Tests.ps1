BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPManager.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate Set-CIPPManager.ps1 at $FunctionPath" }

    function New-GraphBulkRequest { param($Requests, $tenantid) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text) }

    . $FunctionPath
}

Describe 'Set-CIPPManager' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName New-GraphBulkRequest -MockWith {
            foreach ($Request in $Requests) { [pscustomobject]@{ id = $Request.id; status = 204 } }
        }
    }

    It 'resolves a variable once for the tenant the users are in' {
        Mock -CommandName Get-CIPPTextReplacement -MockWith { if ($TenantFilter -eq 'contoso.com') { 'grace@contoso.com' } }

        $Result = Set-CIPPManager -Users 'ada@contoso.com', 'alan@contoso.com' -Manager '%salesmanager%' -TenantFilter 'contoso.com'

        $Result.Success | Should -Be @($true, $true)
        Should -Invoke Get-CIPPTextReplacement -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq 'contoso.com' -and $Text -eq '%salesmanager%' }
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
            $tenantid -eq 'contoso.com' -and @($Requests).Count -eq 2 -and
            @($Requests).Where({ $_.body.'@odata.id' -ne 'https://graph.microsoft.com/beta/users/grace@contoso.com' }).Count -eq 0
        }
    }

    It 'sets no manager when <Case>' -ForEach @(
        @{ Case = 'the variable has no value'; Resolve = { '%salesmanager%' } }
        @{ Case = 'the variable is blank'; Resolve = { ' ' } }
        @{ Case = 'the variable cannot be read'; Resolve = { throw 'Table unavailable' } }
    ) {
        Mock -CommandName Get-CIPPTextReplacement -MockWith $Resolve

        $Result = Set-CIPPManager -Users 'ada@contoso.com' -Manager '%salesmanager%' -TenantFilter 'contoso.com'

        Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
        $Result.Success | Should -BeFalse
        $Result.Result | Should -BeLike "Failed to set ada@contoso.com's manager: *%salesmanager%*contoso.com*"
    }

    It 'sends a user principal name as it is' {
        Mock -CommandName Get-CIPPTextReplacement -MockWith { }

        $Result = Set-CIPPManager -Users 'ada@contoso.com' -Manager 'grace@contoso.com' -TenantFilter 'contoso.com'

        $Result.Success | Should -BeTrue
        Should -Invoke Get-CIPPTextReplacement -Times 0 -Exactly
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
            $Requests[0].method -eq 'PUT' -and $Requests[0].url -eq 'users/ada@contoso.com/manager/$ref' -and
            $Requests[0].body.'@odata.id' -eq 'https://graph.microsoft.com/beta/users/grace@contoso.com'
        }
    }
}
