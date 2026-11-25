BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll') -ErrorAction SilentlyContinue

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function New-GraphPOSTRequest { param($uri, $tenantid, $body, $type, $scope, $AsApp, $maxRetries) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = $Exception.Exception.Message } }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')

    $script:EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Security/Defender/Invoke-ExecDefenderMachineAction.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $script:EndpointPath -Raw)))

    $script:MachineId = 'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678'
    $script:Scope = 'https://api.securitycenter.microsoft.com/.default'

    function New-Principal ([string]$UserDetails) {
        [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes((@{ userDetails = $UserDetails; userRoles = @('editor') } | ConvertTo-Json -Compress)))
    }
    function New-Request ([hashtable]$Body, [hashtable]$Headers = @{ 'x-ms-client-principal' = (New-Principal 'tech@msp.example') }) {
        [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecDefenderMachineAction' }; Headers = $Headers; Body = [pscustomobject]$Body }
    }
    function New-ValidBody ([hashtable]$Extra = @{}) {
        $Body = @{ tenantFilter = 'contoso.onmicrosoft.com'; machineId = $script:MachineId; Action = 'Isolate' }
        foreach ($Key in $Extra.Keys) { $Body[$Key] = $Extra[$Key] }
        $Body
    }
}

Describe 'Invoke-ExecDefenderMachineAction' {
    BeforeEach {
        Mock Write-LogMessage {}
    }

    It 'declares Security.Defender.ReadWrite and accepts one tenant only' {
        $Source = Get-Content -LiteralPath $script:EndpointPath -Raw
        $Source -match '\.FUNCTIONALITY\s*\r?\n\s*(\S+)' | Should -BeTrue
        $Matches[1] | Should -Be 'Entrypoint'
        $Source -match '\.ROLE\s*\r?\n\s*(\S+)' | Should -BeTrue
        $Matches[1] | Should -Be 'Security.Defender.ReadWrite'
    }

    Context 'with Defender stubbed' {
        BeforeEach {
            Mock New-GraphPOSTRequest {
                [pscustomobject]@{ id = 'b7c1e0f2-1111-2222-3333-444455556666'; type = 'Isolate'; status = 'Pending'; machineId = $script:MachineId; computerDnsName = 'mde-lab-w11'; requestorComment = ($body | ConvertFrom-Json).Comment }
            }
        }

        It 'returns 400 without calling Defender when <Case>' -ForEach @(
            @{ Case = 'tenantFilter is missing'; Body = @{ tenantFilter = $null } }
            @{ Case = 'tenantFilter is blank'; Body = @{ tenantFilter = '  ' } }
            @{ Case = 'tenantFilter is a list'; Body = @{ tenantFilter = @('a.com', 'b.com') } }
            @{ Case = 'tenantFilter is AllTenants'; Body = @{ tenantFilter = 'AllTenants' } }
            @{ Case = 'tenantFilter is a tenant group'; Body = @{ tenantFilter = 'group:7f1c' } }
            @{ Case = 'machineId is missing'; Body = @{ machineId = $null } }
            @{ Case = 'machineId is too short'; Body = @{ machineId = 'a1b2c3d4e5f60718293a4b5c6d7e8f901234567' } }
            @{ Case = 'machineId is too long'; Body = @{ machineId = 'a1b2c3d4e5f60718293a4b5c6d7e8f90123456789' } }
            @{ Case = 'machineId is not hexadecimal'; Body = @{ machineId = 'g1b2c3d4e5f60718293a4b5c6d7e8f9012345678' } }
            @{ Case = 'machineId ends in a newline'; Body = @{ machineId = "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678`n" } }
            @{ Case = 'machineId carries a path'; Body = @{ machineId = 'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678/offboard' } }
            @{ Case = 'machineId is a list'; Body = @{ machineId = @('a1b2c3d4e5f60718293a4b5c6d7e8f9012345678') } }
            @{ Case = 'Action is missing'; Body = @{ Action = $null } }
            @{ Case = 'Action is unknown'; Body = @{ Action = 'Offboard' } }
            @{ Case = 'Action is a list'; Body = @{ Action = @('Isolate', 'Scan') } }
            @{ Case = 'IsolationType is invalid'; Body = @{ IsolationType = 'Partial' } }
            @{ Case = 'IsolationType is a list'; Body = @{ IsolationType = @('Full') } }
            @{ Case = 'IsolationType is sent with Scan'; Body = @{ Action = 'Scan'; IsolationType = 'Full' } }
            @{ Case = 'IsolationType is sent with Release'; Body = @{ Action = 'Release'; IsolationType = 'Full' } }
            @{ Case = 'ScanType is invalid'; Body = @{ Action = 'Scan'; ScanType = 'Deep' } }
            @{ Case = 'ScanType is a number'; Body = @{ Action = 'Scan'; ScanType = 1 } }
            @{ Case = 'ScanType is a list'; Body = @{ Action = 'Scan'; ScanType = @('Quick') } }
            @{ Case = 'ScanType is sent with Isolate'; Body = @{ ScanType = 'Quick' } }
            @{ Case = 'Comment is a number'; Body = @{ Comment = 42 } }
            @{ Case = 'Comment is a list'; Body = @{ Comment = @('one', 'two') } }
        ) {
            $Response = Invoke-ExecDefenderMachineAction -Request (New-Request (New-ValidBody $Body))
            $Response.StatusCode | Should -Be 400
            $Response.Body.Results | Should -Not -BeNullOrEmpty
            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        }

        It 'sends <Action> <Subtype> to /<Suffix> with the app token and body <Expected>' -ForEach @(
            @{ Action = 'Isolate'; Subtype = @{}; Suffix = 'isolate'; Expected = @{ IsolationType = 'Full' } }
            @{ Action = 'Isolate'; Subtype = @{ IsolationType = 'Selective' }; Suffix = 'isolate'; Expected = @{ IsolationType = 'Selective' } }
            @{ Action = 'Release'; Subtype = @{}; Suffix = 'unisolate'; Expected = @{} }
            @{ Action = 'Scan'; Subtype = @{}; Suffix = 'runAntiVirusScan'; Expected = @{ ScanType = 'Quick' } }
            @{ Action = 'Scan'; Subtype = @{ ScanType = 'Full' }; Suffix = 'runAntiVirusScan'; Expected = @{ ScanType = 'Full' } }
        ) {
            $Body = New-ValidBody $Subtype
            $Body.Action = $Action
            $Response = Invoke-ExecDefenderMachineAction -Request (New-Request $Body)
            $Response.StatusCode | Should -Be 202
            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
                $Sent = $body | ConvertFrom-Json -AsHashtable
                $Keys = @($Sent.Keys | Sort-Object)
                $uri -ceq "https://api.securitycenter.microsoft.com/api/machines/$($script:MachineId)/$Suffix" -and
                $tenantid -ceq 'contoso.onmicrosoft.com' -and
                $scope -eq $script:Scope -and
                $AsApp -eq $true -and
                $body -is [string] -and
                ($Keys -join ',') -eq (@(@($Expected.Keys) + 'Comment' | Sort-Object) -join ',') -and
                @($Expected.Keys).Where({ $Sent[$_] -cne $Expected[$_] }).Count -eq 0 -and
                $Sent.Comment -ceq 'tech@msp.example via CIPP'
            }
        }

        It 'keeps quotes, backslashes and percent signs in the comment' {
            $Comment = '50% done "quoted" it''s C:\temp'
            $null = Invoke-ExecDefenderMachineAction -Request (New-Request (New-ValidBody @{ Comment = $Comment }))
            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
                ($body | ConvertFrom-Json).Comment -ceq "tech@msp.example via CIPP: $Comment"
            }
        }

        It 'names <Expected> in the comment when the caller is <Case>' -ForEach @(
            @{ Case = 'a signed-in technician'; Headers = @{ 'x-ms-client-principal' = 'PRINCIPAL'; 'x-ms-client-principal-name' = 'ignored@msp.example' }; Expected = 'tech@msp.example' }
            @{ Case = 'an API client'; Headers = @{ 'x-ms-client-principal-idp' = 'aad'; 'x-ms-client-principal-name' = '0b7f1a52-5a0e-4c8e-9f7a-1d2c3b4a5f60' }; Expected = '0b7f1a52-5a0e-4c8e-9f7a-1d2c3b4a5f60' }
            @{ Case = 'unidentified'; Headers = @{}; Expected = 'CIPP' }
        ) {
            if ($Headers['x-ms-client-principal'] -eq 'PRINCIPAL') { $Headers['x-ms-client-principal'] = New-Principal 'tech@msp.example' }
            $null = Invoke-ExecDefenderMachineAction -Request (New-Request (New-ValidBody @{ Comment = 'ticket 4411' }) $Headers)
            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { ($body | ConvertFrom-Json).Comment -ceq "$Expected via CIPP: ticket 4411" }
        }

        It 'returns 202 with the action Defender returned and logs it' {
            Mock New-GraphPOSTRequest {
                [pscustomobject]@{ id = 'existing-pending-action'; type = 'RunAntiVirusScan'; scope = 'Quick'; status = 'InProgress'; machineId = $script:MachineId; computerDnsName = 'mde-lab-w11'; requestorComment = ($body | ConvertFrom-Json).Comment }
            }
            $Response = Invoke-ExecDefenderMachineAction -Request (New-Request (New-ValidBody @{ Action = 'Scan' }))
            $Response.StatusCode | Should -Be 202
            $Response.Body.Results.state | Should -Be 'success'
            $Response.Body.Results.actionId | Should -Be 'existing-pending-action'
            $Response.Body.Results.status | Should -Be 'InProgress'
            $Response.Body.Results.resultText | Should -BeLike '*mde-lab-w11*'
            $Response.Body.Results.resultText | Should -BeLike '*existing-pending-action*'
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
                $sev -eq 'Info' -and $tenant -ceq 'contoso.onmicrosoft.com' -and $message -like '*existing-pending-action*' -and $headers
            }
        }

        It 'names the device by its id when Defender returns no name' {
            Mock New-GraphPOSTRequest { [pscustomobject]@{ id = 'act-2'; status = 'Pending'; requestorComment = ($body | ConvertFrom-Json).Comment } }
            $Response = Invoke-ExecDefenderMachineAction -Request (New-Request (New-ValidBody))
            $Response.Body.Results.resultText | Should -BeLike "*$($script:MachineId)*"
        }

        It 'returns 500 with the Defender message when Defender refuses the action' {
            Mock New-GraphPOSTRequest { throw 'Action is already in progress' }
            $Response = Invoke-ExecDefenderMachineAction -Request (New-Request (New-ValidBody @{ Action = 'Scan' }))
            $Response.StatusCode | Should -Be 500
            $Response.Body.Results | Should -BeLike '*Action is already in progress*'
            $Response.Body.Results | Should -BeLike '*action history*'
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Error' -and $tenant -ceq 'contoso.onmicrosoft.com' -and $headers }
        }

    }
}
