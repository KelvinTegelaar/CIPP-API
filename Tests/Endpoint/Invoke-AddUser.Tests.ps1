# Pester tests for Invoke-AddUser.
#
# The endpoint behind the Add User form. It does very little itself - New-CIPPUserTask does the
# work - but it owns the shape of the response, and that shape is what the operator actually sees.
#
# The first three results are positional: created / username / password, with the last two carrying
# copyField so the UI can offer a copy button. Everything New-CIPPUserTask reports after that -
# licences, group adds, aliases, manager, scheduled shared access - is appended verbatim. That tail
# is where a failed group add surfaces, so dropping or reordering it hides the failure the operator
# needs to see.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/Users/Invoke-AddUser.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate Invoke-AddUser.ps1 at $FunctionPath" }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function New-CIPPUserTask { param($UserObj, $APIName, $Headers) }
    function Add-CIPPScheduledTask { param($Task, $hidden, $Headers, $DisallowDuplicateName) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }

    . $FunctionPath

    function New-AddUserRequest {
        param([hashtable]$Body = @{})
        $RequestBody = [pscustomobject]@{
            tenantFilter = 'contoso.com'
            username     = 'sseck'
            DisplayName  = 'Safiyah Seck'
            PrimDomain   = [pscustomobject]@{ value = 'contoso.com' }
        }
        foreach ($Key in $Body.Keys) {
            $RequestBody | Add-Member -NotePropertyName $Key -NotePropertyValue $Body[$Key] -Force
        }
        [pscustomobject]@{
            Body    = $RequestBody
            Headers = @{}
            Params  = @{ CIPPEndpoint = 'AddUser' }
        }
    }

    # What New-CIPPUserTask hands back: three positional lines then a tail of per-step reports.
    function New-CreationResult {
        param([string[]]$Extra = @())
        [pscustomobject]@{
            Username = 'sseck@contoso.com'
            Password = 'Correct-Horse-Battery'
            User     = [pscustomobject]@{ id = 'user-guid' }
            Results  = @('Created New User.', 'Username: sseck@contoso.com', 'Password: Correct-Horse-Battery') + $Extra
            CopyFrom = [pscustomobject]@{ Success = @(); Error = @() }
        }
    }
}

Describe 'Invoke-AddUser' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Add-CIPPScheduledTask -MockWith { }
        Mock -CommandName New-CIPPUserTask -MockWith { New-CreationResult }
    }

    Context 'Creating the user now' {
        It 'passes the posted body straight through to New-CIPPUserTask' {
            $null = Invoke-AddUser -Request (New-AddUserRequest -Body @{ AddToGroups = @([pscustomobject]@{ label = 'All Office'; value = 'group-dl' }) })

            Should -Invoke New-CIPPUserTask -Times 1 -Exactly -ParameterFilter {
                $UserObj.tenantFilter -eq 'contoso.com' -and
                $UserObj.AddToGroups.value -contains 'group-dl'
            }
        }

        It 'offers the username and password as copyable results' {
            $Response = Invoke-AddUser -Request (New-AddUserRequest)

            $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
            $Response.Body.Results[0] | Should -Be 'Created New User.'
            $Response.Body.Results[1].resultText | Should -Be 'Username: sseck@contoso.com'
            $Response.Body.Results[1].copyField | Should -Be 'sseck@contoso.com'
            $Response.Body.Results[2].copyField | Should -Be 'Correct-Horse-Battery'
        }

        It 'keeps the group results that follow the first three lines' {
            # This tail is where a successful or failed group add is reported.
            Mock -CommandName New-CIPPUserTask -MockWith {
                New-CreationResult -Extra @(
                    'Successfully added user sseck@contoso.com to group All-Users.',
                    'Failed to add to group All Office: Cannot Update a mail-enabled security groups and or distribution list.'
                )
            }

            $Response = Invoke-AddUser -Request (New-AddUserRequest)

            $Response.Body.Results | Should -Contain 'Successfully added user sseck@contoso.com to group All-Users.'
            $Response.Body.Results | Should -Contain 'Failed to add to group All Office: Cannot Update a mail-enabled security groups and or distribution list.'
        }

        It 'keeps a scheduled group retry visible in the response' {
            Mock -CommandName New-CIPPUserTask -MockWith {
                New-CreationResult -Extra @('Could not add sseck@contoso.com to All Office yet (Exchange replication delay). A retry has been scheduled in 15 minutes.')
            }

            $Response = Invoke-AddUser -Request (New-AddUserRequest)

            $Response.Body.Results | Should -Contain 'Could not add sseck@contoso.com to All Office yet (Exchange replication delay). A retry has been scheduled in 15 minutes.'
        }

        It 'surfaces the copy-from group results separately' {
            Mock -CommandName New-CIPPUserTask -MockWith {
                $Result = New-CreationResult
                $Result.CopyFrom = [pscustomobject]@{
                    Success = @('Added user to group: All-Users')
                    Error   = @("We've failed to add the group All Office: boom")
                    Skipped = @('Skipped Dynamic: its membership is set by a dynamic rule, so members cannot be added directly.')
                }
                $Result
            }

            $Response = Invoke-AddUser -Request (New-AddUserRequest)

            $Response.Body.CopyFrom.Success | Should -Contain 'Added user to group: All-Users'
            $Response.Body.CopyFrom.Error | Should -Contain "We've failed to add the group All Office: boom"
            # Groups the copy deliberately left out are part of the outcome, not noise to drop.
            $Response.Body.CopyFrom.Skipped | Should -Contain 'Skipped Dynamic: its membership is set by a dynamic rule, so members cannot be added directly.'
        }

        It 'returns the created user object' {
            $Response = Invoke-AddUser -Request (New-AddUserRequest)

            $Response.Body.User.id | Should -Be 'user-guid'
        }

        It 'reports a creation failure with the collected results' {
            Mock -CommandName New-CIPPUserTask -MockWith { throw @{ 'Results' = @('Failed to create user', 'Username already exists') } }

            $Response = Invoke-AddUser -Request (New-AddUserRequest)

            $Response.StatusCode | Should -Be ([HttpStatusCode]::InternalServerError)
            "$($Response.Body.Results)" | Should -BeLike '*Username already exists*'
        }

        It 'falls back to the exception message when the failure carried no results' {
            Mock -CommandName New-CIPPUserTask -MockWith { throw 'Graph unavailable' }

            $Response = Invoke-AddUser -Request (New-AddUserRequest)

            $Response.StatusCode | Should -Be ([HttpStatusCode]::InternalServerError)
            "$($Response.Body.Results)" | Should -BeLike '*Graph unavailable*'
        }
    }

    Context 'Deferring the creation' {
        It 'schedules New-CIPPUserTask with the whole body instead of creating now' {
            $Request = New-AddUserRequest -Body @{
                Scheduled   = [pscustomobject]@{ Enabled = $true; date = 1785000000 }
                AddToGroups = @([pscustomobject]@{ label = 'All Office'; value = 'group-dl' })
            }

            $Response = Invoke-AddUser -Request $Request

            Should -Invoke New-CIPPUserTask -Times 0 -Exactly
            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
                $Task.Command.value -eq 'New-CIPPUserTask' -and
                $Task.ScheduledTime -eq 1785000000 -and
                $Task.TenantFilter -eq 'contoso.com' -and
                $Task.Parameters.UserObj.AddToGroups.value -contains 'group-dl' -and
                $DisallowDuplicateName -eq $true
            }
            $Response.Body.Results | Should -Contain 'Successfully created scheduled task to create user Safiyah Seck'
        }

        It 'names the scheduled task after the user being created' {
            $Request = New-AddUserRequest -Body @{ Scheduled = [pscustomobject]@{ Enabled = $true; date = 1785000000 } }

            $null = Invoke-AddUser -Request $Request

            Should -Invoke Add-CIPPScheduledTask -Times 1 -Exactly -ParameterFilter {
                $Task.Name -eq 'New user creation: sseck@contoso.com'
            }
        }

        It 'reports a scheduling failure' {
            Mock -CommandName Add-CIPPScheduledTask -MockWith { throw 'scheduler unavailable' }
            $Request = New-AddUserRequest -Body @{ Scheduled = [pscustomobject]@{ Enabled = $true; date = 1785000000 } }

            $Response = Invoke-AddUser -Request $Request

            $Response.StatusCode | Should -Be ([HttpStatusCode]::InternalServerError)
            "$($Response.Body.Results)" | Should -BeLike '*Failed to create scheduled task*scheduler unavailable*'
        }
    }

    Context 'Guard rails' {
        It 'refuses a request with no tenant rather than creating the user somewhere unexpected' {
            $Request = [pscustomobject]@{
                Body    = [pscustomobject]@{ username = 'sseck'; DisplayName = 'Safiyah Seck' }
                Headers = @{}
                Params  = @{ CIPPEndpoint = 'AddUser' }
            }

            $Response = Invoke-AddUser -Request $Request

            $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
            $Response.Body.Results.resultText | Should -Be 'tenantFilter is required to create a user.'
            $Response.Body.Results.state | Should -Be 'error'
            Should -Invoke New-CIPPUserTask -Times 0 -Exactly
            Should -Invoke Add-CIPPScheduledTask -Times 0 -Exactly
        }
    }
}
