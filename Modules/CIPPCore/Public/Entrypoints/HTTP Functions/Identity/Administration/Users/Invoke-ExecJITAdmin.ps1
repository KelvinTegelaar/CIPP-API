using namespace System.Net

Function Invoke-ExecJITAdmin {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Role.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = 'ExecJITAdmin'
    $User = $Request.Headers.'x-ms-client-principal'
    $TenantFilter = $Request.body.TenantFilter.value ? $Request.body.TenantFilter.value : $Request.body.TenantFilter
    Write-LogMessage -user $User -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    if ($Request.Query.Action -eq 'List') {
        $Schema = Get-CIPPSchemaExtensions | Where-Object { $_.id -match '_cippUser' }
        #Write-Information "Schema: $($Schema)"
        $Query = @{
            TenantFilter = $Request.Query.TenantFilter
            Endpoint     = 'users'
            Parameters   = @{
                '$count'  = 'true'
                '$select' = "id,accountEnabled,displayName,userPrincipalName,$($Schema.id)"
                '$filter' = "$($Schema.id)/jitAdminEnabled eq true or $($Schema.id)/jitAdminEnabled eq false"
            }
        }
        $Users = Get-GraphRequestList @Query | Where-Object { $_.id }
        $BulkRequests = $Users | ForEach-Object { @(
                @{
                    id     = $_.id
                    method = 'GET'
                    url    = "users/$($_.id)/memberOf/microsoft.graph.directoryRole/?`$select=id,displayName"
                }
            )
        }
        $RoleResults = New-GraphBulkRequest -tenantid $Request.Query.TenantFilter -Requests @($BulkRequests)
        #Write-Information ($RoleResults | ConvertTo-Json -Depth 10 )
        $Results = $Users | ForEach-Object {
            $MemberOf = ($RoleResults | Where-Object -Property id -EQ $_.id).body.value | Select-Object displayName, id
            [PSCustomObject]@{
                id                 = $_.id
                displayName        = $_.displayName
                userPrincipalName  = $_.userPrincipalName
                accountEnabled     = $_.accountEnabled
                jitAdminEnabled    = $_.($Schema.id).jitAdminEnabled
                jitAdminExpiration = $_.($Schema.id).jitAdminExpiration
                memberOf           = $MemberOf
            }
        }

        #Write-Information ($Results | ConvertTo-Json -Depth 10)
        $Body = @{
            Results  = @($Results)
            Metadata = @{
                Parameters = $Query.Parameters
            }
        }
    } else {

        if ($Request.Body.existingUser.value -match '^[a-f0-9]{8}-([a-f0-9]{4}-){3}[a-f0-9]{12}$') {
            $Username = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($Request.Body.existingUser.value)" -tenantid $TenantFilter).userPrincipalName
        }
        Write-LogMessage -user $User -API $APINAME -message "Executing JIT Admin for $Username" -tenant $TenantFilter -Sev 'Info'

        $Start = ([System.DateTimeOffset]::FromUnixTimeSeconds($Request.Body.StartDate)).DateTime.ToLocalTime()
        $Expiration = ([System.DateTimeOffset]::FromUnixTimeSeconds($Request.Body.EndDate)).DateTime.ToLocalTime()
        $Results = [System.Collections.Generic.List[string]]::new()

        if ($Request.Body.useraction -eq 'Create') {
            Write-LogMessage -user $User -API $APINAME -tenant $TenantFilter -message "Creating JIT Admin user $($Request.Body.Username)" -Sev 'Info'
            Write-Information "Creating JIT Admin user $($Request.Body.username)"
            $JITAdmin = @{
                User         = @{
                    'FirstName'         = $Request.Body.FirstName
                    'LastName'          = $Request.Body.LastName
                    'UserPrincipalName' = "$($Request.Body.Username)@$($Request.Body.Domain.value)"
                }
                Expiration   = $Expiration
                Action       = 'Create'
                TenantFilter = $TenantFilter
            }
            $CreateResult = Set-CIPPUserJITAdmin @JITAdmin
            $Username = "$($Request.Body.Username)@$($Request.Body.Domain.value)"
            $Results.Add("Created User: $($Request.Body.Username)@$($Request.Body.Domain.value)")
            if (!$Request.Body.UseTAP) {
                $Results.Add("Password: $($CreateResult.password)")
            }
            $Results.Add("JIT Admin Expires: $($Expiration)")
            Start-Sleep -Seconds 1
        }

        #Region TAP creation
        if ($Request.Body.UseTAP) {
            try {
                if ($Start -gt (Get-Date)) {
                    $TapParams = @{
                        startDateTime = [System.DateTimeOffset]::FromUnixTimeSeconds($Request.Body.StartDate).DateTime
                    }
                    $TapBody = ConvertTo-Json -Depth 5 -InputObject $TapParams
                } else {
                    $TapBody = '{}'
                }
                # Write-Information "https://graph.microsoft.com/beta/users/$Username/authentication/temporaryAccessPassMethods"
                # Retry creating the TAP up to 10 times, since it can fail due to the user not being fully created yet. Sometimes it takes 2 reties, sometimes it takes 8+. Very annoying. -Bobby
                $Retries = 0
                $MAX_TAP_RETRIES = 10
                do {
                    try {
                        $TapRequest = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($Username)/authentication/temporaryAccessPassMethods" -tenantid $TenantFilter -type POST -body $TapBody
                    } catch {
                        Start-Sleep -Seconds 2
                        Write-Information "ERROR: Run $Retries of $MAX_TAP_RETRIES : Failed to create TAP, retrying"
                        # Write-Information ( ConvertTo-Json -Depth 5 -InputObject (Get-CippException -Exception $_))
                    }
                    $Retries++
                } while ( $null -eq $TapRequest.temporaryAccessPass -and $Retries -le $MAX_TAP_RETRIES )

                $TempPass = $TapRequest.temporaryAccessPass
                $PasswordExpiration = $TapRequest.LifetimeInMinutes

                $PasswordLink = New-PwPushLink -Payload $TempPass
                if ($PasswordLink) {
                    $Password = $PasswordLink
                } else {
                    $Password = $TempPass
                }
                $Results.Add("Temporary Access Pass: $Password")
                $Results.Add("This TAP is usable starting at $($TapRequest.startDateTime) UTC for the next $PasswordExpiration minutes")
            } catch {
                $Results.Add('Failed to create TAP, if this is not yet enabled, use the Standards to push the settings to the tenant.')
                Write-Information (Get-CippException -Exception $_ | ConvertTo-Json -Depth 5)
                if ($Password) {
                    $Results.Add("Password: $Password")
                }
            }
        }
        #EndRegion TAP creation

        $Parameters = @{
            TenantFilter = $TenantFilter
            User         = @{
                'UserPrincipalName' = $Username
            }
            Roles        = $Request.Body.AdminRoles.value
            Action       = 'AddRoles'
            Expiration   = $Expiration
        }
        if ($Start -gt (Get-Date)) {
            $TaskBody = @{
                TenantFilter  = $TenantFilter
                Name          = "JIT Admin (enable): $Username"
                Command       = @{
                    value = 'Set-CIPPUserJITAdmin'
                    label = 'Set-CIPPUserJITAdmin'
                }
                Parameters    = [pscustomobject]$Parameters
                ScheduledTime = $Request.Body.StartDate
                PostExecution = @{
                    Webhook = [bool]($Request.Body.PostExecution | Where-Object -Property value -EQ 'webhook')
                    Email   = [bool]($Request.Body.PostExecution | Where-Object -Property value -EQ 'email')
                    PSA     = [bool]($Request.Body.PostExecution | Where-Object -Property value -EQ 'PSA')
                }
            }
            Add-CIPPScheduledTask -Task $TaskBody -hidden $false
            if ($Request.Body.useraction -ne 'Create') {
                Set-CIPPUserJITAdminProperties -TenantFilter $TenantFilter -UserId $Request.Body.existingUser.value -Expiration $Expiration
            }
            $Results.Add("Scheduling JIT Admin enable task for $Username")
        } else {
            $Results.Add("Executing JIT Admin enable task for $Username")
            Set-CIPPUserJITAdmin @Parameters
        }

        $DisableTaskBody = [pscustomobject]@{
            TenantFilter  = $TenantFilter
            Name          = "JIT Admin ($($Request.Body.ExpireAction.value)): $Username"
            Command       = @{
                value = 'Set-CIPPUserJITAdmin'
                label = 'Set-CIPPUserJITAdmin'
            }
            Parameters    = [pscustomobject]@{
                TenantFilter = $TenantFilter
                User         = @{
                    'UserPrincipalName' = $Username
                }
                Roles        = $Request.Body.AdminRoles.value
                Action       = $Request.Body.ExpireAction.value
            }
            PostExecution = @{
                Webhook = [bool]($Request.Body.PostExecution | Where-Object -Property value -EQ 'webhook')
                Email   = [bool]($Request.Body.PostExecution | Where-Object -Property value -EQ 'email')
                PSA     = [bool]($Request.Body.PostExecution | Where-Object -Property value -EQ 'PSA')
            }
            ScheduledTime = $Request.Body.EndDate
        }
        $null = Add-CIPPScheduledTask -Task $DisableTaskBody -hidden $false
        $Results.Add("Scheduling JIT Admin $($Request.Body.ExpireAction.value) task for $Username")
        $Body = @{
            Results = @($Results)
        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
