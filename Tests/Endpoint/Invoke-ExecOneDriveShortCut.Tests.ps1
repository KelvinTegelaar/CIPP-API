BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }
    function New-CIPPOneDriveShortCut { param($Username, $UserId, $URL, $TenantFilter, $APIName, $Headers, $Destination) }
    . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecOneDriveShortCut.ps1' | Select-Object -First 1).FullName

    function New-Request {
        param($Body)
        [pscustomobject]@{
            Params  = [pscustomobject]@{ CIPPEndpoint = 'ExecOneDriveShortCut' }
            Headers = @{ 'x-ms-client-principal' = 'test' }
            Query   = $null
            Body    = $Body
        }
    }

    function New-Entry {
        param($Username, $Destination = 'shortcuts')
        [pscustomobject]@{
            tenantFilter = 'contoso.com'
            username     = $Username
            userid       = "id-$Username"
            siteUrl      = [pscustomobject]@{ label = 'https://contoso.sharepoint.com/sites/Sales'; value = 'https://contoso.sharepoint.com/sites/Sales' }
            destination  = [pscustomobject]@{ label = 'Shortcuts folder'; value = $Destination }
        }
    }
}

Describe 'Invoke-ExecOneDriveShortCut' {
    BeforeEach {
        # The second user already has the shortcut; everyone else succeeds.
        Mock New-CIPPOneDriveShortCut {
            if ($Username -eq 'two@contoso.com') { throw "Could not add OneDrive shortcut to $Username : nameAlreadyExists" }
            "Successfully created OneDrive Shortcut for $Username"
        }
    }

    It 'attempts every user in a bulk request and reports a failed user in place without stopping' {
        $Body = @((New-Entry 'one@contoso.com'), (New-Entry 'two@contoso.com'), (New-Entry 'three@contoso.com'))
        $Response = Invoke-ExecOneDriveShortCut -Request (New-Request -Body $Body) -TriggerMetadata $null

        $Response.StatusCode | Should -Be 200
        Should -Invoke New-CIPPOneDriveShortCut -Times 3 -Exactly
        $Results = @($Response.Body.Results)
        $Results.Count | Should -Be 4
        $Results[0].state | Should -Be 'success'
        $Results[1].state | Should -Be 'error'
        $Results[1].resultText | Should -Match 'two@contoso.com'
        $Results[2].state | Should -Be 'success'
        $Results[2].resultText | Should -Match 'three@contoso.com'
        $Results[3].state | Should -Be 'warning'
        $Results[3].resultText | Should -Match '2 of 3'
    }

    It 'unwraps the site and destination selections and forwards them per user' {
        $Body = @((New-Entry 'one@contoso.com' -Destination 'root'), (New-Entry 'three@contoso.com'))
        $null = Invoke-ExecOneDriveShortCut -Request (New-Request -Body $Body) -TriggerMetadata $null

        Should -Invoke New-CIPPOneDriveShortCut -Times 1 -ParameterFilter {
            $Username -eq 'one@contoso.com' -and $UserId -eq 'id-one@contoso.com' -and $URL -eq 'https://contoso.sharepoint.com/sites/Sales' -and $Destination -eq 'root' -and $TenantFilter -eq 'contoso.com'
        }
        Should -Invoke New-CIPPOneDriveShortCut -Times 1 -ParameterFilter {
            $Username -eq 'three@contoso.com' -and $Destination -eq 'shortcuts'
        }
    }

    It 'still accepts a single object from the user page and keeps the old success shape' {
        $Response = Invoke-ExecOneDriveShortCut -Request (New-Request -Body (New-Entry 'one@contoso.com')) -TriggerMetadata $null

        $Response.StatusCode | Should -Be 200
        $Results = @($Response.Body.Results)
        $Results.Count | Should -Be 1
        $Results[0].state | Should -Be 'success'
        $Results[0].resultText | Should -Match 'one@contoso.com'
    }

    It 'defaults a missing destination to root' {
        $Entry = New-Entry 'one@contoso.com'
        $Entry.destination = $null
        $null = Invoke-ExecOneDriveShortCut -Request (New-Request -Body $Entry) -TriggerMetadata $null
        Should -Invoke New-CIPPOneDriveShortCut -Times 1 -ParameterFilter { $Destination -eq 'root' }
    }

    It 'returns an error status only when every user failed' {
        $Single = Invoke-ExecOneDriveShortCut -Request (New-Request -Body (New-Entry 'two@contoso.com')) -TriggerMetadata $null
        $Single.StatusCode | Should -Be 500
        @($Single.Body.Results)[0].state | Should -Be 'error'

        $Bulk = Invoke-ExecOneDriveShortCut -Request (New-Request -Body @((New-Entry 'two@contoso.com'), (New-Entry 'two@contoso.com'))) -TriggerMetadata $null
        $Bulk.StatusCode | Should -Be 500
        $Results = @($Bulk.Body.Results)
        $Results.Count | Should -Be 3
        $Results[2].state | Should -Be 'error'
        $Results[2].resultText | Should -Match '0 of 2'
    }

    It 'rejects an empty body' {
        $Response = Invoke-ExecOneDriveShortCut -Request (New-Request -Body $null) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 400
        Should -Invoke New-CIPPOneDriveShortCut -Times 0
    }
}
