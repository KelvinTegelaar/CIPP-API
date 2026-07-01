# Pester tests for Invoke-EditUser
# Validates the clear-vs-omit behaviour of the user PATCH body:
# a profile field present in the request (even as null) is forwarded to Graph as a clear,
# while an omitted field is left untouched.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/Users/Invoke-EditUser.ps1'
    $CorePath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPUser.ps1'

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    # The Functions worker exposes [HttpStatusCode]; map it for standalone test runs.
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) $Exception }
    # Capture the body of the user PATCH (first call; password reset is a separate call we don't trigger)
    function New-GraphPostRequest {
        param($uri, $tenantid, $type, $body, [switch]$verbose)
        if ($null -eq $script:lastBody) { $script:lastBody = $body }
    }
    function Add-CIPPScheduledTask {
        param($Task, $hidden, $DisallowDuplicateName, $Headers)
        $script:lastScheduledTask = $Task
    }

    function New-EditRequest {
        param([hashtable]$Extra)
        $body = [pscustomobject]@{
            id           = '11111111-1111-1111-1111-111111111111'
            tenantFilter = 'contoso.onmicrosoft.com'
            username     = 'jdoe'
            Domain       = 'contoso.com'
            displayName  = 'John Doe'
        }
        foreach ($key in $Extra.Keys) {
            $body | Add-Member -NotePropertyName $key -NotePropertyValue $Extra[$key] -Force
        }
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'EditUser' }
            Headers = @{}
            Body    = $body
        }
    }

    . $CorePath
    . $FunctionPath
}

Describe 'Invoke-EditUser body construction' {
    BeforeEach {
        $script:lastBody = $null
    }

    It 'clears a field listed in clearProperties' {
        $request = New-EditRequest -Extra @{ clearProperties = @('jobTitle') }

        $null = Invoke-EditUser -Request $request -TriggerMetadata $null

        $script:lastBody | Should -Match '"jobTitle":null'
    }

    It 'omits a field that was neither sent nor listed for clearing' {
        $request = New-EditRequest -Extra @{}

        $null = Invoke-EditUser -Request $request -TriggerMetadata $null

        $script:lastBody | Should -Not -Match 'jobTitle'
    }

    It 'sends a provided value unchanged' {
        $request = New-EditRequest -Extra @{ jobTitle = 'Manager' }

        $null = Invoke-EditUser -Request $request -TriggerMetadata $null

        $script:lastBody | Should -Match '"jobTitle":"Manager"'
    }

    It 'clears a collection field with an empty array' {
        $request = New-EditRequest -Extra @{ clearProperties = @('otherMails') }

        $null = Invoke-EditUser -Request $request -TriggerMetadata $null

        $script:lastBody | Should -Match '"otherMails":\[\]'
    }

    It 'never clears displayName even when listed (Graph rejects it)' {
        $request = New-EditRequest -Extra @{ clearProperties = @('displayName') }

        $null = Invoke-EditUser -Request $request -TriggerMetadata $null

        $script:lastBody | Should -Not -Match '"displayName":(null|"")'
    }
}

Describe 'Invoke-EditUser scheduling' {
    BeforeEach {
        $script:lastBody = $null
        $script:lastScheduledTask = $null
    }

    It 'schedules a Set-CIPPUser task instead of editing immediately when Scheduled.Enabled is set' {
        $request = New-EditRequest -Extra @{ Scheduled = @{ Enabled = $true; date = 1234567890 } }

        $null = Invoke-EditUser -Request $request -TriggerMetadata $null

        $script:lastBody | Should -BeNullOrEmpty
        $script:lastScheduledTask.Command.value | Should -Be 'Set-CIPPUser'
        $script:lastScheduledTask.Parameters.UserObj.id | Should -Be $request.Body.id
        $script:lastScheduledTask.ScheduledTime | Should -Be 1234567890
    }
}
